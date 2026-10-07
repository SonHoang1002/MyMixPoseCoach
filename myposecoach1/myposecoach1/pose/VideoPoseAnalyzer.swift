import Foundation
import MediaPipeTasksVision
import UIKit

// Nhận diện khung xương trên chuỗi khung hình VIDEO.
//
// Chế độ VIDEO khác chế độ ảnh tĩnh ở điểm quyết định: **nó có BÁM (tracking)**.
// Dò người một lần rồi bám qua các khung hình sau, giống hệt camera thời gian thực.
//
// ⚠️ Chính vì vậy đây là **cách duy nhất kiểm được rủi ro số 1 của dự án mà không
// cần điện thoại**: cho video người xoay lưng chạy qua đây, xem bám được tới góc
// bao nhiêu thì đứt. Ảnh tĩnh không kiểm được, vì mỗi ảnh là một lần dò độc lập,
// không có gì để bám.
//
// Ba chế độ chạy của MediaPipe, ánh xạ 1-1 với ba chỗ gọi trong sản phẩm:
//     image      → phân tích ảnh mẫu            (StillPoseAnalyzer)
//     video      → chấm khung hình sau khi quay  ← FILE NÀY
//     liveStream → camera thời gian thực         (PoseDetector)
//
// Cả ba đều trả về cùng kiểu [PoseFrame], dựng bằng cùng hàm [PoseFrame.from] —
// đây là bất biến "cùng một hàm" của dự án, không được phá.
//
// Chế độ VIDEO chạy ĐỒNG BỘ: gọi xong có kết quả ngay. Phải gọi từ luồng nền.
nonisolated final class VideoPoseAnalyzer: @unchecked Sendable {

    private let lock = NSLock()
    private var landmarker: PoseLandmarker?
    /// Mốc thời gian khung hình trước, để ép tăng nghiêm ngặt.
    private var lastTimestamp: Int64 = -1

    init(modelAsset: String = PoseDetector.MODEL_FULL,
         delegate: Delegate = .CPU,
         minPoseDetectionConfidence: Float = 0.5,
         minTrackingConfidence: Float = 0.5) {
        do {
            let baseOptions = BaseOptions()
            baseOptions.modelAssetPath = PoseDetector.modelAssetPath(for: modelAsset)
            baseOptions.delegate = delegate

            let options = PoseLandmarkerOptions()
            options.baseOptions = baseOptions
            options.runningMode = .video
            options.numPoses = 1
            options.minPoseDetectionConfidence = minPoseDetectionConfidence
            options.minTrackingConfidence = minTrackingConfidence

            // Tạo bộ nhận diện phải đi qua khoá dùng chung — tạo đồng thời với bộ khác sẽ
            // làm app sập bằng SIGBUS trong tầng C++ (FOOTGUNS mục 17).
            landmarker = try MediaPipeGuard.shared.serialized {
                try PoseLandmarker(options: options)
            }
        } catch {
            NSLog("VideoPoseAnalyzer: Không nạp được model cho chế độ video — \(error)")
            landmarker = nil
        }
    }

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return landmarker != nil
    }

    /// Phân tích một khung hình.
    ///
    /// [timestampMs] phải **tăng nghiêm ngặt** giữa các lần gọi, nếu không MediaPipe
    /// ném lỗi. Hàm tự ép điều đó, nhưng bên gọi vẫn nên truyền mốc thật của video
    /// để cơ chế bám hoạt động đúng nhịp.
    ///
    /// Trả `PoseFrame` rỗng khi model chạy được nhưng không thấy người — khác với
    /// `nil` (không nạp được model). Hai tình huống này phải phân biệt.
    ///
    /// - Parameter image: khung hình ĐÃ dựng đúng chiều (VideoFrameSource đã áp
    ///   transform của video qua `appliesPreferredTrackTransform`).
    func analyze(image: UIImage, timestampMs: Int64) -> PoseFrame? {
        lock.lock()
        let lm = landmarker
        let ts = timestampMs > lastTimestamp ? timestampMs : lastTimestamp + 1
        lastTimestamp = ts
        lock.unlock()
        guard let lm else { return nil }

        do {
            let mpImage: MPImage
            do {
                mpImage = try MPImage(uiImage: image)
            } catch {
                NSLog("VideoPoseAnalyzer: Không tạo được MPImage — \(error)")
                return nil
            }
            let result = try lm.detect(videoFrame: mpImage,
                                       timestampInMilliseconds: Int(ts))
            let landmarks = result.landmarks
            if landmarks.isEmpty {
                return PoseFrame(points: [], visibility: [], world: [], timestampMs: ts)
            } else {
                return PoseFrame.from(
                    landmarks: landmarks[0],
                    worldLandmarks: result.worldLandmarks.first ?? [],
                    timestampMs: ts,
                )
            }
        } catch {
            NSLog("VideoPoseAnalyzer: Lỗi khi phân tích khung hình video — \(error)")
            return nil
        }
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        MediaPipeGuard.shared.serialized {
            landmarker = nil
        }
    }
}
