import Foundation
import ImageIO
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
// **Bất biến quan trọng nhất được giữ ở đây:** ảnh mẫu và khung hình camera đều đi
// ra cùng một kiểu [PoseFrame], dựng bằng cùng một engine [VisionPose].
//
// Trước đây bọc MediaPipe (nạp model một lần rồi dùng lại). Nay Vision không cần
// nạp model — mỗi lần gọi dựng request mới, không có tài nguyên phải giữ, nên bỏ
// hẳn phần "ensureLandmarker"/khoá dùng chung.
nonisolated enum StillPoseAnalyzer {

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
        guard let cg = image.cgImage else {
            NSLog("StillPoseAnalyzer: UIImage không có CGImage.")
            return nil
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return VisionPose.frame(fromCGImage: cg, orientation: orientation)
    }

    /// Giữ lại cho tương thích API cũ. Vision không có tài nguyên phải giải phóng.
    static func release() {}
}
