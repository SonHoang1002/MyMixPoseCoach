import Foundation
import MediaPipeTasksVision
import UIKit

// Lớp bọc quanh MediaPipe Pose Landmarker.
//
// Đây là "cầu nối nền tảng" — phần khó nhất và dễ sai nhất khi chuyển từ Android
// sang iOS. Nguyên tắc: mọi thứ đặc thù MediaPipe dừng lại ở file này; các tầng
// trên chỉ nhận [PoseFrame] đã chuẩn hoá.
//
// Ba mức model, đổi được lúc chạy để đo (TONG_QUAN §7.4):
//   lite  — nhanh nhất, kém chính xác nhất
//   full  — MẶC ĐỊNH, cân bằng (toolkit khuyến nghị bắt đầu từ đây)
//   heavy — chính xác nhất, chậm nhất (ML Kit không có mức này)
//
// Ba running mode của MediaPipe ánh xạ 1-1 với ba chỗ gọi:
//     image      → phân tích ảnh mẫu            (StillPoseAnalyzer)
//     video      → chấm khung hình sau khi quay  (VideoPoseAnalyzer)
//     liveStream → camera thời gian thực         (FILE NÀY)
nonisolated final class PoseDetector: NSObject, PoseLandmarkerLiveStreamDelegate, @unchecked Sendable {

    struct Config {
        var modelAsset: String = MODEL_FULL
        /// CPU hay GPU. FOOTGUNS: GPU KHÔNG phải lúc nào cũng nhanh hơn, và đã có
        /// báo cáo lỗi khi xoay màn hình với model lite + GPU. Phải đo cả hai trên
        /// máy thật rồi mới chọn — đừng mặc định GPU.
        var delegate: Delegate = .CPU
        var minPoseDetectionConfidence: Float = 0.5
        var minPosePresenceConfidence: Float = 0.5
        var minTrackingConfidence: Float = 0.5
        /// Số người tối đa. >1 để còn khoá đúng một chủ thể khi nhiều người trong khung.
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
    /// Gọi mỗi khi có kết quả. Chạy trên luồng nền của MediaPipe, KHÔNG phải luồng giao diện.
    private let onResult: (PoseFrame, InferenceStats) -> Void
    private let onError: (String) -> Void
    /// Khung hình ĐÃ XOAY ĐÚNG CHIỀU, để nơi khác dùng lại.
    ///
    /// Hiện chỉ dùng cho nhận diện khuôn mặt thời gian thực. Ảnh chân dung lấy
    /// hướng mẫu và góc ngửa/chúc từ khuôn mặt.
    ///
    /// ⚠️ Dùng lại đúng tấm khung này thay vì giải mã lần nữa: giải mã và xoay là
    /// phần đắt nhất của vòng lặp, làm hai lần là tự cắt đôi tốc độ khung hình.
    ///
    /// ⚠️ Chạy trên LUỒNG CAMERA. Bên nhận phải trả về ngay và đẩy việc nặng sang
    /// luồng khác, nếu không camera nghẽn.
    private let onFrameImage: ((UIImage) -> Void)?

    /// Khoá bảo vệ [landmarker].
    ///
    /// ⚠️ BẮT BUỘC. Luồng phân tích của camera gọi [detect] còn luồng giao diện
    /// gọi [close]. Nếu đóng đúng lúc một khung hình đang được gửi đi, MediaPipe
    /// sẽ gọi vào vùng nhớ vừa giải phóng và **sập ở tầng C++** (SIGSEGV/SIGBUS)
    /// — không phải lỗi Swift nên không có thông báo nào, app chỉ tắt ngóm.
    private let lock = NSLock()

    private var landmarker: PoseLandmarker?

    /// Thời điểm gửi khung hình đi, để tính thời gian nhận diện khi kết quả quay về.
    private var sentAtMs: Int64 = 0

    /// Mốc thời gian của khung hình gửi gần nhất. MediaPipe ở chế độ LIVE_STREAM đòi
    /// mốc thời gian phải TĂNG NGHIÊM NGẶT; hai khung hình rơi vào cùng một mili-giây
    /// sẽ làm nó ném lỗi. Máy càng nhanh càng dễ dính.
    private var lastSentTimestamp: Int64 = 0

    private var lastInputWidth = 0
    private var lastInputHeight = 0
    private var lastRotation = 0

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return landmarker != nil
    }

    init(config: Config = Config(),
         onResult: @escaping (PoseFrame, InferenceStats) -> Void,
         onError: @escaping (String) -> Void,
         onFrameImage: ((UIImage) -> Void)? = nil) {
        self.config = config
        self.onResult = onResult
        self.onError = onError
        self.onFrameImage = onFrameImage
        super.init()
    }

    func setup() {
        close()
        do {
            let baseOptions = BaseOptions()
            baseOptions.modelAssetPath = Self.modelAssetPath(for: config.modelAsset)
            baseOptions.delegate = config.delegate

            let options = PoseLandmarkerOptions()
            options.baseOptions = baseOptions
            options.minPoseDetectionConfidence = config.minPoseDetectionConfidence
            options.minPosePresenceConfidence = config.minPosePresenceConfidence
            options.minTrackingConfidence = config.minTrackingConfidence
            options.numPoses = config.numPoses
            // LIVE_STREAM: kết quả trả về BẤT ĐỒNG BỘ qua delegate. Không được
            // chờ kết quả trong luồng camera - sẽ nghẽn (FOOTGUNS mục 4 của
            // camera-and-pose.md).
            options.runningMode = .liveStream
            options.poseLandmarkerLiveStreamDelegate = self

            // Tạo phải đi qua khoá dùng chung (FOOTGUNS mục 17).
            let created = try MediaPipeGuard.shared.serialized {
                try PoseLandmarker(options: options)
            }
            lock.lock()
            landmarker = created
            lastSentTimestamp = 0
            lock.unlock()
        } catch {
            // Nguyên nhân hay gặp nhất: thiếu file model trong bundle, hoặc tên
            // tài nguyên sai (phải là "pose_landmarker_full.task" — KHÔNG đóng
            // gói nén như Android).
            NSLog("PoseDetector: Không khởi tạo được bộ nhận diện — \(error)")
            onError("Không nạp được model nhận diện: \(error.localizedDescription)")
        }
    }

    func close() {
        lock.lock()
        // Tạo/huỷ phải đi qua khoá dùng chung. iOS không có landmarker.close();
        // gán nil là huỷ — MediaPipeGuard.serialized bọc đúng lúc này (FOOTGUNS 17).
        MediaPipeGuard.shared.serialized {
            landmarker = nil
        }
        lock.unlock()
    }

    /// Đưa một khung hình từ camera vào nhận diện.
    ///
    /// Gọi từ luồng phân tích của camera. Hàm này trả về NGAY, kết quả tới sau
    /// qua [onResult]. Bên gọi không phải giữ pixel buffer sau khi hàm trả về
    /// (MPImage retain trong suốt thời gian detectAsync xử lý).
    ///
    /// - Parameter pixelBuffer: khung BGRA từ `AVCaptureVideoDataOutput`
    ///   (bắt buộc `kCVPixelFormatType_32BGRA`, xem MPPPoseLandmarker.h).
    /// - Parameter orientationDegrees: góc quay ĐỂ HIỂN THỊ đúng chiều, degrees.
    ///   Khớp `imageInfo.rotationDegrees` của CameraX: 0/90/180/270.
    func detect(pixelBuffer: CVPixelBuffer, orientationDegrees: Int = 0) {
        // Kiểm nhanh trước khi làm việc nặng, tránh xử lý vô ích khi đã đóng.
        lock.lock()
        let lm = landmarker
        lock.unlock()
        if lm == nil { return }

        // MediaPipe iOS áp rotation theo orientation của MPImage (xem MPPImage.h):
        // inference chạy trên bản sao ĐÃ XOAY theo orientation. Không cần xoay
        // pixels tay như bản Android (Bitmap.rotate) — giữ nguyên kết quả toạ độ
        // trong khung hình dựng đứng.
        let orientation = Self.uiOrientation(fromDegrees: orientationDegrees)
        let mpImage: MPImage
        do {
            mpImage = try MPImage(pixelBuffer: pixelBuffer, orientation: orientation)
        } catch {
            onError("Không tạo được MPImage từ khung camera — \(error.localizedDescription)")
            return
        }

        // Kích thước SAU khi xoay — khớp với bitmap đã rotate của bản Android,
        // vì MediaPipe cũng chạy inference trên ảnh đã xoay.
        let srcW = Int(mpImage.width)
        let srcH = Int(mpImage.height)
        let upright = orientationDegrees % 180 != 0

        // Toàn bộ phần chạm vào MediaPipe nằm trong khoá. `detectAsync` trả về ngay
        // (xử lý thật diễn ra ở luồng khác của thư viện) nên giữ khoá ở đây không
        // gây nghẽn camera.
        lock.lock()
        guard let lm2 = landmarker else {
            lock.unlock()
            return
        }

        lastInputWidth = upright ? srcH : srcW
        lastInputHeight = upright ? srcW : srcH
        lastRotation = orientationDegrees

        // Ép mốc thời gian tăng nghiêm ngặt. Hai khung hình rơi vào cùng một
        // mili-giây sẽ làm MediaPipe ném lỗi ở chế độ LIVE_STREAM.
        let now = Self.uptimeMs()
        let ts = now > lastSentTimestamp ? now : lastSentTimestamp + 1
        sentAtMs = ts
        lastSentTimestamp = ts

        do {
            _ = try lm2.detectAsync(image: mpImage, timestampInMilliseconds: Int(ts))
        } catch {
            lock.unlock()
            onError("Lỗi khi gửi khung hình vào bộ nhận diện: \(error.localizedDescription)")
            return
        }
        lock.unlock()

        // Ảnh khung cho nơi khác dùng lại: UIImage mang đúng imageOrientation =
        // góc đã truyền vào. Tầng sau đi qua MPImage(uiImage:) sẽ tự xoay theo
        // orientation này — không phải giải mã/xoay lại.
        if let cgImage = Self.copyCGImage(from: pixelBuffer) {
            onFrameImage?(UIImage(cgImage: cgImage, scale: 1, orientation: orientation))
        }
    }

    /// Tiện cho đường ảnh UIImage đã dựng đứng (không qua camera).
    func detect(image: UIImage) {
        lock.lock()
        let lm = landmarker
        lock.unlock()
        if lm == nil { return }

        // MPImage(uiImage:) lấy orientation từ chính UIImage (imageOrientation) —
        // đúng thứ UprightBitmap trả về.
        let mpImage: MPImage
        do {
            mpImage = try MPImage(uiImage: image)
        } catch {
            onError("Không tạo được MPImage từ UIImage — \(error.localizedDescription)")
            return
        }

        let w = Int(mpImage.width)
        let h = Int(mpImage.height)

        lock.lock()
        guard let lm2 = landmarker else {
            lock.unlock()
            return
        }

        lastInputWidth = w
        lastInputHeight = h
        lastRotation = 0

        let now = Self.uptimeMs()
        let ts = now > lastSentTimestamp ? now : lastSentTimestamp + 1
        sentAtMs = ts
        lastSentTimestamp = ts

        do {
            _ = try lm2.detectAsync(image: mpImage, timestampInMilliseconds: Int(ts))
        } catch {
            lock.unlock()
            onError("Lỗi khi gửi khung hình vào bộ nhận diện: \(error.localizedDescription)")
            return
        }
        lock.unlock()

        onFrameImage?(image)
    }

    // Delegate của PoseLandmarker — chạy trên luồng riêng của thư viện MediaPipe,
    // KHÔNG phải MainActor. Không dispatch về main ở đây (Android cũng vậy).
    func poseLandmarker(_ poseLandmarker: PoseLandmarker,
                        didFinishDetection result: PoseLandmarkerResult?,
                        timestampInMilliseconds: Int,
                        error: Error?) {
        if let error {
            onError(error.localizedDescription)
            return
        }
        guard let result else { return }

        lock.lock()
        let sent = sentAtMs
        let stats = InferenceStats(inferenceTimeMs: Self.uptimeMs() - sent,
                                   inputWidth: lastInputWidth,
                                   inputHeight: lastInputHeight,
                                   rotationDegrees: lastRotation)
        lock.unlock()

        let landmarks = result.landmarks
        if landmarks.isEmpty {
            onResult(PoseFrame(points: [], visibility: [], world: [], timestampMs: Int64(result.timestampInMilliseconds)), stats)
            return
        }
        // numPoses = 1 nên chỉ có một người. Khi bật nhiều người, chỗ này là nơi
        // sẽ cắm logic khoá chủ thể (chọn khung bao lớn nhất rồi bám theo).
        let world = result.worldLandmarks.first ?? []
        onResult(
            PoseFrame.from(landmarks: landmarks[0],
                           worldLandmarks: world,
                           timestampMs: Int64(result.timestampInMilliseconds)),
            stats,
        )
    }

    // MARK: - Helpers

    /// Mốc thời gian monotonous (uptime) tính bằng mili-giây — tương đương
    /// `SystemClock.uptimeMillis()` của Android.
    static func uptimeMs() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    /// Ánh xạ góc CameraX → UIImage.Orientation để MPImage tự xoay khi inference.
    ///
    /// 90° CameraX (xoay 90° CW để hiển thị đúng) ↔ `.right` (MediaPipe xoay 90° CW).
    static func uiOrientation(fromDegrees degrees: Int) -> UIImage.Orientation {
        switch ((degrees % 360) + 360) % 360 {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    /// Đường dẫn ABSOLUTE tới model trong bundle app. MediaPipe iOS cần đường dẫn
    /// tuyệt đối, khác Android (asset name tương đối trong APK).
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
