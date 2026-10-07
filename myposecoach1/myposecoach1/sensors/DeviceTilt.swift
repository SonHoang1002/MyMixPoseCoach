import CoreMotion
import Foundation

// Đọc độ nghiêng của máy từ cảm biến.
//
// Nuôi hai thứ:
//   - Mục 4 (máy ngửa/chúc) — tiêu chí DUY NHẤT được siết tới 5°, vì cảm biến
//     chính xác dưới 1°. Mọi tiêu chí khác phải nới rộng hơn nhiều.
//   - Tốc độ góc — dùng cho cổng chống chụp lúc tay đang đưa (15°/s), cơ chế
//     đóng băng hướng dẫn khi lắc mạnh (45°/s), và loại khung hình rung khi
//     chọn ảnh.
//
// ⚠️ Lấy từ VECTOR TRỘNG LỰC, không lấy từ góc quay tổng hợp của hệ thống.
// Bài học của bản iOS cũ: dùng `attitude.pitch` bị "khoá gimbal" khi cầm máy
// dựng đứng — đúng tư thế chụp ảnh dọc mà app này dùng nhiều nhất.
//
// ⚠️ BẪY TRỤC CẢM BIẾN Android → iOS (bắt buộc đọc trước khi sửa):
//
//   Android TYPE_GRAVITY (quy ước gia tốc kế, vector chỉ HƯỚNG LÊN):
//     đặt máy nằm ngửa trên bàn  → (0, 0, +9.81)
//     cầm dọc, ống kính nhìn ngang → (0, +9.81, 0)
//     nằm sấp, ống kính nhìn lên trời → (0, 0, −9.81)
//
//   CoreMotion deviceMotion.gravity (vector chỉ HƯỚNG XUỐNG — gia tốc trọng trường):
//     đặt máy nằm ngửa trên bàn  → (0, 0, −1)
//     cầm dọc, ống kính nhìn ngang → (0, −1, 0)
//     nằm sấp, ống kính nhìn lên trời → (0, 0, +1)
//
//   → CẢ BA TRỤC ĐỀU ĐẢO NGƯỢC (không chỉ Z). Đảo dấu x, y, z của CoreMotion
//     để trở về quy ước Android, rồi DÙNG NGUYÊN công thức gốc — không viết
//     lại công thức khác, không đổi ngưỡng.
//
// CMMotionManager.deviceMotion gộp cả gravity lẫn rotationRate trong một bản
// kết hợp (IMU fusion) — tương đương TYPE_GRAVITY + TYPE_GYROSCOPE của Android.
nonisolated final class DeviceTilt: @unchecked Sendable {

    struct Reading {
        /// Góc ngẩng của trục ống kính so với MẶT PHẲNG NGANG, độ.
        /// Dương = máy ngửa lên trời. Âm = máy chúc xuống đất. 0 = ngang.
        var cameraPitchDeg: Double = 0
        /// Độ vẹo chân trời, độ. Chỉ đọc để tự nắn ảnh, KHÔNG dùng để hướng dẫn.
        var rollDeg: Double = 0
        /// Tốc độ quay của máy, độ/giây. Càng lớn = tay càng đang di chuyển.
        var angularSpeedDegPerSec: Double = 0
        var hasData: Bool = false
    }

    private let motionManager = CMMotionManager()
    /// Queue nền cho callback cảm biến — KHÔNG được dùng MainActor (sẽ chậm, vỡ 350ms).
    private let queue: OperationQueue
    private let lock = NSLock()
    private var _state = Reading()

    /// SENSOR_DELAY_GAME của Android = 20.000 micro-giây ≈ 0,02s.
    /// Brief iOS chốt `.33s` — chênh ~16× so với Android. GIỮ theo brief chốt;
    /// nếu đo thấy cổng 15°/s / 45°/s chậm thì sửa đúng một chỗ này.
    private let updateInterval: TimeInterval = 0.33

    init() {
        queue = OperationQueue()
        queue.name = "DeviceTilt"
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
    }

    /// Máy này có đủ cảm biến không. Thiếu con quay hồi chuyển là hỏng 4 thứ (FOOTGUNS mục 2).
    var hasGravity: Bool { motionManager.isDeviceMotionAvailable }
    var hasGyroscope: Bool { motionManager.isGyroAvailable }

    var state: Reading {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handle(deviceMotion: motion)
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    private func handle(deviceMotion: CMDeviceMotion) {
        // --- Cách suy góc ngẩng của ống kính ---
        // Hệ trục iOS (máy cầm dọc, nhìn vào màn hình) — GIỐNG Android:
        //   x sang phải · y lên phía đỉnh máy · z hướng ra phía người dùng
        // Camera SAU nhìn theo hướng ngược lại màn hình, tức trục (0, 0, −1).
        //
        // ĐẢO DẤU vector CoreMotion để về quy ước TYPE_GRAVITY (hướng LÊN),
        // rồi giữ nguyên công thức Android:
        //
        // sin(góc ngẩng) = tích vô hướng của trục ống kính với hướng lên
        //                = (0,0,−1) · g_android/|g|
        //                = −gz / |g|
        //
        // Kiểm lại bằng 3 tư thế (sau khi đã đảo dấu CoreMotion):
        //   nằm ngửa trên bàn (camera chúc xuống đất): gz=+1  → −90° ✓
        //   cầm dọc bình thường (camera nhìn ngang):   gy=+1  → 0°   ✓
        //   nằm sấp trên bàn (camera nhìn lên trời):   gz=−1  → +90° ✓
        let g = deviceMotion.gravity
        let gx = -Double(g.x)
        let gy = -Double(g.y)
        let gz = -Double(g.z)
        let mag = (gx * gx + gy * gy + gz * gz).squareRoot()
        if mag >= 1e-6 {
            let sinPitch = min(max(-gz / mag, -1.0), 1.0)
            let pitch = sinPitch * 180.0 / Double.pi

            // Độ vẹo. Dấu cần kiểm lại trên máy thật, nhưng KHÔNG gấp: tài liệu
            // chốt là không hướng dẫn người dùng nắn vẹo, chỉ tự nắn ảnh dưới 3°.
            let roll = atan2(-gx, gy) * 180.0 / Double.pi

            lock.lock()
            _state.cameraPitchDeg = pitch
            _state.rollDeg = roll
            _state.hasData = true
            lock.unlock()
        }

        // Con quay trả về radian/giây quanh 3 trục. Lấy độ lớn tổng hợp.
        // Độ lớn KHÔNG phụ thuộc dấu trục — không cần đảo gì với rotationRate.
        let r = deviceMotion.rotationRate
        let speed = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot() * 180.0 / Double.pi

        lock.lock()
        _state.angularSpeedDegPerSec = speed
        lock.unlock()
    }
}
