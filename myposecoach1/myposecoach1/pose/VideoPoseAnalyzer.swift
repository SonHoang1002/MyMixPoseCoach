import Foundation
import ImageIO
import MediaPipeTasksVision
import UIKit

// Nhận diện khung xương trên chuỗi khung hình VIDEO (quét lại video đã quay).
//
// Chế độ VIDEO của MediaPipe có tracking qua các khung, giống đường Android.
//
// Ba chế độ trước đây của MediaPipe, ánh xạ 1-1 với ba chỗ gọi trong sản phẩm:
//     ảnh mẫu          → StillPoseAnalyzer
//     khung hình video → FILE NÀY
//     camera live      → PoseDetector
//
// Đồng bộ: gọi xong có kết quả ngay. Phải gọi từ luồng nền.
nonisolated final class VideoPoseAnalyzer: @unchecked Sendable {

    private let lock = NSLock()
    private var closed = false
    private var landmarker: PoseLandmarker?
    private var useVisionFallback = false
    private var lastTimestampMs: Int64 = -1

    init(modelAsset: String = PoseDetector.MODEL_FULL,
         minPoseDetectionConfidence: Float = 0.5,
         minTrackingConfidence: Float = 0.5) {
        do {
            landmarker = try MediaPipePose.makeLandmarker(
                mode: .video,
                modelAsset: modelAsset,
                minDetection: minPoseDetectionConfidence,
                minTracking: minTrackingConfidence
            )
        } catch {
            useVisionFallback = true
            NSLog("VideoPoseAnalyzer: MediaPipe không sẵn sàng, dùng Vision fallback — \(error)")
        }
    }

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed && (landmarker != nil || useVisionFallback)
    }

    /// Phân tích một khung hình.
    ///
    /// Trả `PoseFrame` rỗng khi không thấy người — khác với `nil` (không chạy được
    /// request). Hai tình huống này phải phân biệt.
    ///
    /// - Parameter image: khung hình ĐÃ dựng đúng chiều (VideoFrameSource đã áp
    ///   transform của video qua `appliesPreferredTrackTransform`).
    /// - Parameter timestampMs: mốc thời gian của khung hình; gắn vào kết quả.
    func analyze(image: UIImage, timestampMs: Int64) -> PoseFrame? {
        lock.lock()
        let daDong = closed
        lock.unlock()
        guard !daDong else { return nil }
        let timestamp = max(timestampMs, lastTimestampMs + 1)
        lastTimestampMs = timestamp
        if let landmarker {
            do {
                let result = try landmarker.detect(
                    videoFrame: MediaPipePose.image(image),
                    timestampInMilliseconds: Int(timestamp)
                )
                return MediaPipePose.frame(from: result, timestampMs: timestamp)
            } catch {
                NSLog("VideoPoseAnalyzer: MediaPipe inference thất bại — \(error)")
                return nil
            }
        }
        guard let cg = image.cgImage,
              let frame = VisionPose.frame(
                fromCGImage: cg,
                orientation: CGImagePropertyOrientation(image.imageOrientation)
              ) else { return nil }
        return PoseFrame(points: frame.points, visibility: frame.visibility,
                         world: frame.world, timestampMs: timestamp)
    }

    func close() {
        lock.lock()
        closed = true
        landmarker = nil
        lock.unlock()
    }
}
