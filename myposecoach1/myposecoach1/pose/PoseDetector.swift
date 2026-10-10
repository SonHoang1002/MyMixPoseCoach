import CoreVideo
import CoreImage
import Foundation
import ImageIO
import UIKit

// Lớp bọc nhận diện khung xương thời gian thực (camera).
//
// Trước đây bọc MediaPipe Pose Landmarker ở chế độ LIVE_STREAM. Nay dùng Apple
// Vision (`VisionPose`) — cùng kiểu đầu ra [PoseFrame], nên tầng trên không đổi.
//
// Lý do đổi: MediaPipeTasksVision 1.0.0 sập trên iOS 27 (driver Metal AGX). Vision
// là framework hệ điều hành, không có pipeline Metal riêng. Xem `VisionPose.swift`.
//
// API công khai giữ NGUYÊN so với bản MediaPipe để các chỗ gọi khỏi sửa:
//   setup() / close() / isReady / detect(pixelBuffer:orientationDegrees:) / detect(image:)
//
// Ba running mode cũ ánh xạ 1-1 với ba chỗ gọi:
//     ảnh mẫu            → StillPoseAnalyzer
//     chấm khung video   → VideoPoseAnalyzer
//     camera thời gian thực → FILE NÀY
nonisolated final class PoseDetector: @unchecked Sendable {

    struct Config {
        var modelAsset: String = MODEL_FULL
        var minPoseDetectionConfidence: Float = 0.5
        var minPosePresenceConfidence: Float = 0.5
        var minTrackingConfidence: Float = 0.5
        /// Số người tối đa. Vision hiện trả người nổi bật nhất; >1 dành cho tương lai.
        var numPoses: Int = 1
    }

    /// Số liệu hiệu năng của một lần nhận diện — nuôi bảng đo ở màn hình gỡ lỗi.
    struct InferenceStats {
        var inferenceTimeMs: Int64
        var inputWidth: Int
        var inputHeight: Int
        var rotationDegrees: Int
    }

    private let config: Config
    /// Gọi mỗi khi có kết quả. Chạy trên luồng nền, KHÔNG phải luồng giao diện.
    private let onResult: (PoseFrame, InferenceStats) -> Void
    private let onError: (String) -> Void
    /// Khung hình ĐÃ DỰNG ĐÚNG CHIỀU cho nơi khác dùng lại (nhận diện khuôn mặt).
    /// Chỉ dựng khi có người nhận — dựng ảnh cần CIContext, chỉ làm khi thật cần.
    private let onFrameImage: ((UIImage) -> Void)?

    /// Khoá bảo vệ cờ trạng thái.
    ///
    /// ⚠️ BẮT BUỘC. Luồng camera gọi [detect] còn luồng giao diện gọi [close]. Phải
    /// chặn không cho khung hình mới khởi động sau khi chủ đã bỏ rơi bộ nhận diện.
    private let lock = NSLock()

    /// Hàng đợi suy luận — Vision chạy ĐỒNG BỘ, tách khỏi luồng camera để không nghẽn.
    private let queue = DispatchQueue(label: "com.posecoach.poseDetector.vision",
                                      qos: .userInitiated)

    private var ready = false

    /// Chủ đã gọi [close] rồi — `setup()` chạy SAU đó (nạp chạy nền, có thể về muộn
    /// hơn lúc người dùng rời màn) thì KHÔNG được đánh thức lại.
    private var closed = false

    /// Đang có một khung hình chạy suy luận. Khung mới tới trong lúc bận sẽ BỎ —
    /// thà bỏ khung còn hơn xếp hàng làm trễ hình.
    private var busy = false

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ready && !closed
    }

    init(config: Config = Config(),
         onResult: @escaping (PoseFrame, InferenceStats) -> Void,
         onError: @escaping (String) -> Void,
         onFrameImage: ((UIImage) -> Void)? = nil) {
        self.config = config
        self.onResult = onResult
        self.onError = onError
        self.onFrameImage = onFrameImage
    }

    /// Vision không cần nạp model, nhưng giữ nguyên API: `setup()` chỉ đánh dấu sẵn
    /// sàng. Chạy được cả trên luồng nền (tương thích cách gọi cũ).
    func setup() {
        lock.lock()
        if !closed { ready = true }
        lock.unlock()
    }

    func close() {
        lock.lock()
        closed = true
        ready = false
        lock.unlock()
    }

    /// Đưa một khung hình từ camera vào nhận diện.
    ///
    /// Gọi từ luồng phân tích của camera. Hàm trả về NGAY; kết quả tới sau qua
    /// [onResult]. Bên gọi KHÔNG phải giữ pixel buffer sau khi hàm trả về — buffer
    /// được giữ tới khi suy luận xong.
    ///
    /// - Parameter pixelBuffer: khung BGRA từ `AVCaptureVideoDataOutput`.
    /// - Parameter orientationDegrees: góc quay ĐỂ HIỂN THỊ đúng chiều. Khớp
    ///   `imageInfo.rotationDegrees` của CameraX: 0/90/180/270.
    func detect(pixelBuffer: CVPixelBuffer, orientationDegrees: Int = 0) {
        lock.lock()
        if !ready || closed || busy {
            lock.unlock()
            return
        }
        busy = true
        lock.unlock()

        // Vision áp hướng xoay lên ảnh trước khi suy khớp — không xoay pixel tay.
        let orientation = VisionPose.cgOrientation(fromDegrees: orientationDegrees)
        let upright = ((orientationDegrees % 360) + 360) % 360 % 180 != 0
        let rawW = CVPixelBufferGetWidth(pixelBuffer)
        let rawH = CVPixelBufferGetHeight(pixelBuffer)
        // Kích thước SAU khi xoay — khớp tỉ lệ khung mà tầng cắt hình dùng để crop.
        let srcW = upright ? rawH : rawW
        let srcH = upright ? rawW : rawH
        let sent = Self.uptimeMs()

        queue.async { [weak self] in
            guard let self else { return }
            let frame = VisionPose.frame(fromPixelBuffer: pixelBuffer,
                                         orientation: orientation)

            self.lock.lock()
            self.busy = false
            let daDong = self.closed
            self.lock.unlock()
            if daDong { return }

            guard let frame else {
                self.onError("Không chạy được nhận diện khung xương (Vision).")
                return
            }
            let stats = InferenceStats(inferenceTimeMs: Self.uptimeMs() - sent,
                                       inputWidth: srcW,
                                       inputHeight: srcH,
                                       rotationDegrees: orientationDegrees)
            self.onResult(frame, stats)

            // Chỉ dựng ảnh khung khi có người nhận (tránh CIContext vô ích). Khung
            // rỗng = không thấy người → không có mặt để nhận diện, bỏ luôn.
            if !frame.isEmpty, let onFrameImage = self.onFrameImage,
               let cg = Self.copyCGImage(from: pixelBuffer) {
                onFrameImage(UIImage(cgImage: cg, scale: 1,
                                     orientation: UIImage.Orientation(orientation)))
            }
        }
    }

    /// Đường ảnh UIImage đã dựng đứng (không qua camera).
    func detect(image: UIImage) {
        lock.lock()
        if !ready || closed || busy {
            lock.unlock()
            return
        }
        busy = true
        lock.unlock()

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let sent = Self.uptimeMs()

        queue.async { [weak self] in
            guard let self else { return }
            let frame = image.cgImage.flatMap {
                VisionPose.frame(fromCGImage: $0, orientation: orientation)
            }

            self.lock.lock()
            self.busy = false
            let daDong = self.closed
            self.lock.unlock()
            if daDong { return }

            self.onFrameImage?(image)
            guard let frame else {
                self.onError("Không chạy được nhận diện khung xương (Vision).")
                return
            }
            let stats = InferenceStats(inferenceTimeMs: Self.uptimeMs() - sent,
                                       inputWidth: image.cgImage?.width ?? Int(image.size.width),
                                       inputHeight: image.cgImage?.height ?? Int(image.size.height),
                                       rotationDegrees: 0)
            self.onResult(frame, stats)
        }
    }

    private var onFrameImageWanted: Bool { onFrameImage != nil }

    // MARK: - Helpers

    /// Mốc thời gian monotonous (uptime) tính bằng mili-giây — tương đương
    /// `SystemClock.uptimeMillis()` của Android.
    static func uptimeMs() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    /// Đường dẫn ABSOLUTE tới model trong bundle. Giữ lại cho API tương thích cũ;
    /// Vision không dùng.
    static func modelAssetPath(for assetName: String) -> String {
        let ns = assetName as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension.isEmpty ? "task" : ns.pathExtension
        if let path = Bundle.main.path(forResource: base, ofType: ext) {
            return path
        }
        return assetName
    }

    private static func copyCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return sharedCIContext.createCGImage(ciImage, from: ciImage.extent)
    }

    /// Dùng chung một CIContext — tạo mới mỗi khung hình camera là tự làm chậm vòng lặp.
    private static let sharedCIContext = CIContext(options: nil)

    static let MODEL_LITE = "pose_landmarker_lite.task"
    static let MODEL_FULL = "pose_landmarker_full.task"
    static let MODEL_HEAVY = "pose_landmarker_heavy.task"
}
