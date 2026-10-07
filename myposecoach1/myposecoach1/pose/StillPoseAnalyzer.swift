import Foundation
import MediaPipeTasksVision
import UIKit

// Nhận diện khung xương trên MỘT ẢNH TĨNH.
//
// ⚠️ ĐÂY KHÔNG PHẢI CÔNG CỤ THỬ NGHIỆM TẠM. Đây chính là đường mà sản phẩm dùng
// để **phân tích ảnh mẫu** — bước đầu tiên của toàn bộ chuỗi:
//
//     ảnh mẫu → StillPoseAnalyzer → PoseFrame → quy ra số → so với camera live
//
// Ba chế độ chạy của MediaPipe ánh xạ 1-1 với ba chỗ gọi trong sản phẩm:
//     image      → phân tích ảnh mẫu            ← FILE NÀY
//     video      → chấm khung hình sau khi quay  (VideoPoseAnalyzer)
//     liveStream → camera thời gian thực         (PoseDetector)
//
// **Bất biến quan trọng nhất được giữ ở đây:** ảnh mẫu và khung hình camera đều đi
// ra cùng một kiểu [PoseFrame], dựng bằng cùng một hàm [PoseFrame.from].
//
// ⚠️ **DÙNG LẠI một bộ nhận diện, KHÔNG tạo mới mỗi lần gọi.** Bản trước tạo rồi
// huỷ mỗi lần phân tích một ảnh — vừa lãng phí (nạp lại model 9MB mỗi lần), vừa
// làm app sập khi tạo/huỷ chồng chéo với bộ nhận diện của camera. Xem FOOTGUNS
// mục 17.
nonisolated enum StillPoseAnalyzer {

    /// Khoá bảo vệ bộ nhận diện dùng chung — tạo/huỷ phải bọc MediaPipeGuard (FOOTGUNS 17).
    private static let lock = NSLock()
    private static var landmarker: PoseLandmarker?
    private static var loadedModel: String?

    /// Phân tích một ảnh. Trả về nil nếu không nạp được model.
    /// Trả về [PoseFrame] rỗng nếu model chạy được nhưng **không thấy người nào** —
    /// hai tình huống khác nhau, bên gọi phải phân biệt để báo cho người dùng đúng
    /// nguyên nhân (nguyên tắc "không thất bại im lặng").
    ///
    /// Chạy ĐỒNG BỘ, phải gọi từ luồng nền.
    ///
    /// - Parameter image: ảnh ĐÃ dựng đúng chiều. Nếu UIImage còn mang
    ///   `imageOrientation` (EXIF), MPImage tự xoay theo — không cần xoay tay.
    /// - Parameter modelAsset: tên asset trong bundle, mặc định model full.
    static func analyze(image: UIImage,
                        modelAsset: String = PoseDetector.MODEL_FULL) -> PoseFrame? {
        lock.lock()
        defer { lock.unlock() }

        guard let lm = ensureLandmarker(modelAsset: modelAsset) else { return nil }
        do {
            let mpImage: MPImage
            do {
                mpImage = try MPImage(uiImage: image)
            } catch {
                NSLog("StillPoseAnalyzer: Không tạo được MPImage — \(error)")
                return nil
            }

            let result = try lm.detect(image: mpImage)
            let landmarks = result.landmarks
            if landmarks.isEmpty {
                return PoseFrame(points: [], visibility: [], world: [], timestampMs: 0)
            } else {
                return PoseFrame.from(
                    landmarks: landmarks[0],
                    worldLandmarks: result.worldLandmarks.first ?? [],
                    timestampMs: 0,
                )
            }
        } catch {
            NSLog("StillPoseAnalyzer: Không phân tích được ảnh — \(error)")
            return nil
        }
    }

    /// Tạo bộ nhận diện nếu chưa có, hoặc nếu đổi sang model khác.
    /// **GỌI KHI ĐÃ GIỮ lock.**
    private static func ensureLandmarker(modelAsset: String) -> PoseLandmarker? {
        if let lm = landmarker, loadedModel == modelAsset { return lm }
        do {
            // Ảnh tĩnh chạy một lần, không cần nhanh — CPU cho chắc.
            let baseOptions = BaseOptions()
            baseOptions.modelAssetPath = PoseDetector.modelAssetPath(for: modelAsset)
            baseOptions.delegate = .CPU

            let options = PoseLandmarkerOptions()
            options.baseOptions = baseOptions
            options.runningMode = .image
            options.numPoses = 1

            // Tạo phải đi qua khoá dùng chung (FOOTGUNS mục 17).
            let created = try MediaPipeGuard.shared.serialized {
                landmarker = nil
                return try PoseLandmarker(options: options)
            }
            landmarker = created
            loadedModel = modelAsset
            return created
        } catch {
            NSLog("StillPoseAnalyzer: Không nạp được model cho chế độ ảnh tĩnh — \(error)")
            return nil
        }
    }

    /// Giải phóng. Gọi khi app đóng hẳn; bình thường cứ giữ để dùng lại.
    static func release() {
        lock.lock()
        defer { lock.unlock() }
        MediaPipeGuard.shared.serialized {
            landmarker = nil
        }
        loadedModel = nil
    }
}
