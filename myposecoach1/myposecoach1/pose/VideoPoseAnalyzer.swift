import Foundation
import ImageIO
import UIKit

// Nhận diện khung xương trên chuỗi khung hình VIDEO (quét lại video đã quay).
//
// Trước đây dùng chế độ VIDEO của MediaPipe (có BÁM/tracking qua các khung hình).
// Vision không có bám liên khung — mỗi khung hình dò độc lập. Về mặt số liệu, đầu
// ra vẫn là cùng kiểu [PoseFrame]; chỉ khác là có thể "rung" hơn khi người cử động
// nhanh. Chấp nhận được cho đường "chấm khung hình sau khi quay".
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

    init(modelAsset: String = PoseDetector.MODEL_FULL,
         minPoseDetectionConfidence: Float = 0.5,
         minTrackingConfidence: Float = 0.5) {
        // Vision không nạp model — giữ tham số cho tương thích API cũ.
    }

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed
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
        guard !daDong, let cg = image.cgImage else { return nil }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        guard let frame = VisionPose.frame(fromCGImage: cg, orientation: orientation) else {
            return nil
        }
        return PoseFrame(points: frame.points,
                         visibility: frame.visibility,
                         world: frame.world,
                         timestampMs: timestampMs)
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
    }
}
