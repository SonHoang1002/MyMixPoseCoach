import Foundation
import ImageIO
import MediaPipeTasksVision
import UIKit

// Nhận diện khung xương trên MỘT ẢNH TĨNH.
//
// ⚠️ ĐÂY KHÔNG PHẢI CÔNG CỤ THỬ NGHIỆM TẠM. Đây chính là đường mà sản phẩm dùng
// để **phân tích ảnh mẫu** — bước đầu tiên của toàn bộ chuỗi:
//
//     ảnh mẫu → StillPoseAnalyzer → PoseFrame → quy ra số → so với camera live
//
// Ba chế độ trước đây của MediaPipe ánh xạ 1-1 với ba chỗ gọi trong sản phẩm:
//     ảnh mẫu          → FILE NÀY
//     khung hình video → VideoPoseAnalyzer
//     camera live      → PoseDetector
//
// **Bất biến quan trọng nhất:** ảnh mẫu và camera đều dùng cùng MediaPipe Full và
// cùng hàm chuyển đổi `MediaPipePose.frame`. Vision chỉ dùng khi MediaPipe lỗi.
nonisolated enum StillPoseAnalyzer {
    private static let lock = NSLock()
    private static var landmarker: PoseLandmarker?
    private static var loadedModel: String?
    private static var useVisionFallback = false

    /// Phân tích một ảnh. Trả về nil nếu KHÔNG chạy được request của Vision.
    /// Trả về [PoseFrame] rỗng nếu chạy được nhưng **không thấy người nào** —
    /// hai tình huống khác nhau, bên gọi phải phân biệt để báo cho người dùng đúng
    /// nguyên nhân (nguyên tắc "không thất bại im lặng").
    ///
    /// Chạy ĐỒNG BỘ, phải gọi từ luồng nền.
    ///
    /// - Parameter image: ảnh ĐÃ dựng đúng chiều. Nếu UIImage còn mang
    ///   `imageOrientation` (EXIF), Vision tự xoay theo — không cần xoay tay.
    /// - Parameter modelAsset: giữ lại cho tương thích API cũ; Vision không dùng.
    static func analyze(image: UIImage,
                        modelAsset: String = PoseDetector.MODEL_FULL) -> PoseFrame? {
        lock.lock()
        defer { lock.unlock() }
        if landmarker == nil, !useVisionFallback {
            do {
                landmarker = try MediaPipePose.makeLandmarker(mode: .image, modelAsset: modelAsset)
                loadedModel = modelAsset
            } catch {
                useVisionFallback = true
                NSLog("StillPoseAnalyzer: MediaPipe không sẵn sàng, dùng Vision fallback — \(error)")
            }
        } else if loadedModel != nil, loadedModel != modelAsset {
            landmarker = nil
            loadedModel = nil
            do {
                landmarker = try MediaPipePose.makeLandmarker(mode: .image, modelAsset: modelAsset)
                loadedModel = modelAsset
            } catch {
                useVisionFallback = true
            }
        }
        if let landmarker {
            do {
                return MediaPipePose.frame(
                    from: try landmarker.detect(image: MediaPipePose.image(image)),
                    timestampMs: 0
                )
            } catch {
                NSLog("StillPoseAnalyzer: MediaPipe inference thất bại — \(error)")
                return nil
            }
        }
        guard let cg = image.cgImage else { return nil }
        return VisionPose.frame(fromCGImage: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
    }

    /// Giữ lại cho tương thích API cũ. Vision không có tài nguyên phải giải phóng.
    static func release() {
        lock.lock()
        landmarker = nil
        loadedModel = nil
        lock.unlock()
    }
}
