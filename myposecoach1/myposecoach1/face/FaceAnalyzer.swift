import CoreVideo
import Foundation
import ImageIO
import UIKit
import Vision

// Nhận diện khuôn mặt bằng Apple Vision — phản vai trò `FaceAnalyzer` (ML Kit)
// của Android, nhưng iOS chỉ cần một thứ ML Kit có mà code thật sự dùng:
// **góc quay trái/phải của mặt** (`FaceInfo.yawDeg`, nguồn `.faceYaw` cho lớp
// CHEST/HEAD ở `FramingClass.yawSource`).
//
// ## Vì sao dùng `VNDetectFaceRectanglesRequest`
//
// `VNFaceObservation.yaw` (radian, ±π/2 ≈ ±90°) do chính request này dựng sẵn —
// không cần thêm dependency, đúng kim chỉ nam "ưu tiên package có sẵn của iOS".
//
// Trước khi có file này, iOS KHÔNG có bộ nhận diện mặt → `FaceInfo.yawDeg` luôn
// `nil` ở CẢ ảnh mẫu lẫn khung camera → mục HƯỚNG MẪU với ảnh chân dung/bán thân
// mãi ở trạng thái UNMEASURED: không đạt, không hướng dẫn, chỉ im lặng chờ bỏ qua
// (đúng kiểu "mục tưởng có mà chạy là tắt" mà dự án cấm). Xem
// `CAC_MUC_HUONG_DAN_CHI_TIET_IOS.md` §7.
//
// ## Hệ toạ độ
//
// Cùng quy ước với `VisionPose`: Vision xoay ảnh theo orientation trước khi suy,
// nên góc trả về nằm trong hệ của ảnh ĐÃ DỰNG ĐÚNG CHIỀU — đúng không gian mà khung
// xương của camera/ảnh mẫu đang nằm, nên so 1-1 được (`angleDiff`).
//
// ## `eyesOpen` còn nil trên iOS
//
// `VNDetectFaceRectanglesRequest` không đo độ mở mắt; cách dựng từ
// `VNDetectFaceLandmarksRequest` (đoán theo EAR của mi mắt) không đủ tin cậy để
// chấm điểm. Mục MẮT MỞ là hậu kỳ, trọng số 0,06 → iOS trả `nil`, `TemplateProfile`
// tự bỏ và ghi lý do, đúng luật "không đo được thì bỏ ra, không trừ điểm".
nonisolated enum FaceAnalyzer {

    /// Nhận diện mặt trong một khung hình camera (pixels THÔ + orientation) —
    /// đối thủ đúng của đường `VisionPose.frame(fromPixelBuffer:orientation:)`.
    static func face(from pixelBuffer: CVPixelBuffer,
                     orientation: CGImagePropertyOrientation) -> FaceInfo? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])
        return run(handler: handler)
    }

    /// Nhận diện mặt trong một ảnh ĐÃ dựng đúng chiều (ảnh mẫu). Nếu UIImage còn
    /// mang `imageOrientation` (EXIF), Vision tự xoay theo — không cần xoay tay.
    static func face(from image: UIImage) -> FaceInfo? {
        guard let cg = image.cgImage else { return nil }
        return face(fromCGImage: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
    }

    static func face(fromCGImage image: CGImage,
                     orientation: CGImagePropertyOrientation) -> FaceInfo? {
        let handler = VNImageRequestHandler(cgImage: image,
                                            orientation: orientation,
                                            options: [:])
        return run(handler: handler)
    }

    private static func run(handler: VNImageRequestHandler) -> FaceInfo? {
        let request = VNDetectFaceRectanglesRequest()
        do {
            try handler.perform([request])
        } catch {
            NSLog("FaceAnalyzer: request thất bại — \(error)")
            return nil
        }
        // ⚠️ QUYẾT ĐỊNH: vì `yawSource` so bằng `angleDiff` (độ lệch tuyệt đối, không
        // phân biệt trái/phải — ShotScore.yawDeviation), CHỈ cần hai bên cùng thang.
        // Dấu của `VNFaceObservation.yaw` phải kiểm trên máy thật cùng buổi đo với
        // `bodyYawDeg` (CAC_MUC_HUONG_DAN_CHI_TIET_IOS.md §7 / §9).
        guard let obs = request.results?.first as? VNFaceObservation,
              let rad = obs.yaw?.doubleValue else {
            return nil
        }
        return FaceInfo(yawDeg: rad * 180.0 / Double.pi)
    }
}

/// Khoá tần suất chạy nhận diện mặt trên CAMERA live.
///
/// Camera chạy ~30fps, mỗi khung đã có pose + 3D + vẽ khung xương. Mặt CHỈ cần mới
/// trong `FACE_TOI_DA_MS` (600ms) mới nhất, nên chạy ~300ms/lần là dư giả — chạy
/// mỗi khung là tự làm chậm vòng lặp mà không đổi kết quả (`CaptureViewModel` bỏ
/// giá trị cũ quá 600ms).
nonisolated final class FaceThrottle: @unchecked Sendable {
    private let intervalMs: Int64
    private let lock = NSLock()
    private var lastAtMs: Int64 = 0

    init(intervalMs: Int64) {
        self.intervalMs = intervalMs
    }

    /// `true` nếu đã đủ thời gian kể từ lần chạy trước — và tự đánh dấu "đã chạy".
    func allow() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        guard now - lastAtMs >= intervalMs else { return false }
        lastAtMs = now
        return true
    }
}