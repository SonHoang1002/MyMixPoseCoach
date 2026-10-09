import AVFoundation
import UIKit

// CAMERA THẬT cho màn chụp — xem trước, nhận diện thời gian thực, và **quay video**.
//
// Vì sao phải quay video thật thay vì lưu lại khung hình đã nhận diện: khung hình
// đưa vào bộ nhận diện chỉ khoảng 640px (cố ý, cho nhanh). Lưu chúng ra làm ảnh
// cuối thì ảnh xấu — và tệ hơn, ta sẽ **tự trả lời sai** câu hỏi lớn nhất của dự
// án (*"khung cắt từ video có đẹp bằng ảnh chụp thường không"*). Quay 1080p rồi
// cắt khung mới đúng thiết kế đã chốt.
//
// Đây là bộ điều khiển camera DUY NHẤT của app — bản iOS tương đương
// `camera/CaptureController.kt` của Android.
//
// ## BỐN KHÁC BIỆT NỀN TẢNG PHẢI HIỂU TRƯỚC KHI SỬA
//
// 1. **Không có LifecycleOwner / PreviewView.** CameraX gắn camera vào vòng đời
//    Activity; AVFoundation thì `AVCaptureSession` sống độc lập. Xem trước đi qua
//    `previewLayer` (màn chụp dựng `UIView` bọc nó), còn vòng đời do app tự giữ
//    qua `start()` / `stop()`.
//
// 2. **Khung hình camera về khung CẢM BIẾN, không tự dựng đứng.** `AVCaptureVideoDataOutput`
//    trả buffer theo chiều của cảm biến (luôn ngang); ta truyền `orientationDegrees`
//    cho `PoseDetector` để Vision tự xoay — đúng như `ImageProxy.imageInfo.rotationDegrees`
//    của CameraX. Riêng ảnh chụp liên tục và video thì ghi hướng qua
//    `AVCaptureConnection.videoRotationAngle` (ảnh ra EXIF, video ra track transform).
//
// 3. **Không có `ImageCapture` + `VideoCapture` chạy song song.** CameraX chỉ bảo
//    đảm 3 use case ở mức `LIMITED`; AVFoundation thì thêm bao nhiêu output cũng
//    được — nên ta giữ nguyên Ý ĐỊNH của bản Android: mỗi chế độ gắn đúng bộ output
//    nó cần (chụp liên tục gắn `AVCapturePhotoOutput`, quay video gắn
//    `AVCaptureMovieFileOutput`), luôn kèm `AVCaptureVideoDataOutput` cho nhận diện.
//
// 4. **Bốn chiều quay máy đọc từ `UIDevice`, không đọc từ accelerometer.**
//    `OrientationEventListener` của Android tự suy góc từ gia tốc kế; iOS không
//    có API tương đương, `UIDevice.orientation` cũng lấy từ gia tốc kế nên giữ
//    nguyên được lớp chặn 400ms (xem [GIU_HUONG_MS]).
final class CaptureController {

    // -----------------------------------------------------------------
    // Kiểu ngoài
    // -----------------------------------------------------------------

    /// HAI CÁCH BẮT ẢNH, người dùng chọn.
    ///
    /// Bản iOS có cả hai và bản Android trước đây chỉ có [Mode.video]. Chúng KHÔNG
    /// thay thế nhau — mỗi cách mạnh ở một tình huống khác hẳn:
    ///
    /// | | [Mode.video] | [Mode.burst] |
    /// |---|---|---|
    /// | Bắt được gì | mọi khoảnh khắc trong 15-30 giây | 8 khoảnh khắc quanh lúc bấm |
    /// | Chất lượng mỗi ảnh | khung cắt từ video (thấp hơn) | **ảnh chụp thật, full độ phân giải** |
    /// | Hợp với | mẫu đang cử động, cười nói tự nhiên | mẫu đã vào dáng, chỉ chờ đúng lúc |
    /// | Rác sinh ra | 60-100 MB video thô | vài MB ảnh |
    ///
    /// ⚠️ [Mode.burst] còn trả lời hộ câu hỏi lớn nhất của dự án — *"ảnh cắt từ
    /// video có đẹp bằng ảnh chụp thường không"* — vì giờ hai đường nằm cạnh nhau
    /// trong cùng một app, so trực tiếp được.
    enum Mode {
        case video
        case burst
    }

    /// HƯỚNG MÁY — bốn chiều như `DeviceRotation` của Android.
    ///
    /// ⚠️ Đọc kỹ mục 3 dưới đây trước khi đổi `videoRotationAngle`.
    enum DeviceRotation {
        case portrait
        case landscapeLeft
        case portraitUpsideDown
        case landscapeRight

        var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }

        /// Góc quay ĐỒNG HỒ (độ) cần áp cho khung cảm biến để ra ảnh dựng đứng.
        ///
        /// Suy từ đúng hai dữ kiện, không đoán:
        ///
        /// - `UIDeviceOrientation.landscapeLeft` nghĩa là **đỉnh máy hướng sang
        ///   TRÁI** (Apple/StackOverflow: *"the top of your phone is on the left"*),
        ///   và `UIDeviceOrientation` ↔ `AVCaptureVideoOrientation` bị ĐẢO tên nhau
        ///   ở chiều ngang.
        /// - `AVCaptureVideoOrientation.landscapeRight` cho EXIF **1** (không cần
        ///   xoay), `.landscapeLeft` cho EXIF **3** (xoay 180°).
        ///
        ///   → máy quay trái (đỉnh hướng trái) thì khung cảm biến dựng đứng SẴN, 0°.
        ///
        ///   Kiểm lại bằng máy ảo: máy nằm ngửa bình thường, xoay 90° ngược chiều
        ///   kim đồng hồ thì đỉnh máy hướng trái — lúc đó ảnh cảm biến không cần
        ///   xoay nữa.
        ///
        /// ⚠️ `portrait` = 90° và `portraitUpsideDown` = 270° là hai con số chắc
        /// chắn nhất của AVFoundation; hai chiều ngang thì nên kiểm lại một lần trên
        /// máy thật trước khi tin (chưa có máy trong tay).
        ///
        /// ⚠️ CÙNG một giá trị cho camera trước và camera sau. `videoRotationAngle`
        /// là góc xoay áp cho BUFFER, còn cảm biến trước/sau cùng khai orientation —
        /// đổi khác nhau là khung xương vẽ lên khung xem trước lệch 180° so với phép
        /// đo mà không có lỗi nào báo ra.
        var videoRotationAngle: CGFloat {
            switch self {
            case .portrait: return 90
            case .portraitUpsideDown: return 270
            case .landscapeLeft: return 0
            case .landscapeRight: return 180
            }
        }

        /// Góc truyền cho `PoseDetector.detect(pixelBuffer:orientationDegrees:)`.
        ///
        /// Khung cảm biến CHƯA được xoay (xem mục 2 của chú thích đầu file), nên
        /// đúng là `videoRotationAngle` — khớp `imageInfo.rotationDegrees` của CameraX.
        var orientationDegrees: Int { Int(videoRotationAngle) }

        /// Từ `UIDeviceOrientation`. `nil` = faceUp/faceDown/unknown — tương đương
        /// `OrientationEventListener.ORIENTATION_UNKNOWN` của Android.
        static func from(deviceOrientation: UIDeviceOrientation) -> DeviceRotation? {
            switch deviceOrientation {
            case .portrait: return .portrait
            case .portraitUpsideDown: return .portraitUpsideDown
            case .landscapeLeft: return .landscapeLeft
            case .landscapeRight: return .landscapeRight
            default: return nil
            }
        }

        /// Từ hướng giao diện — dùng khi `UIDevice` chưa đọc được hướng
        /// (app vừa mở, máy nằm ngửa).
        ///
        /// ⚠️ Hai chiều ngang ĐẢO tên nhau: `UIDeviceOrientation.landscapeLeft`
        /// == `UIInterfaceOrientation.landscapeRight`.
        static func from(interfaceOrientation: UIInterfaceOrientation) -> DeviceRotation? {
            switch interfaceOrientation {
            case .portrait: return .portrait
            case .portraitUpsideDown: return .portraitUpsideDown
            case .landscapeLeft: return .landscapeRight
            case .landscapeRight: return .landscapeLeft
            default: return nil
            }
        }
    }

    // -----------------------------------------------------------------
    // Chỉ số camera
    // -----------------------------------------------------------------

    /// Tỉ lệ ngang/dọc của cảm biến 4:3 khi cầm dọc.
    private static let TI_LE_4_3_DOC = 3.0 / 4.0

    /// Hướng mới phải giữ được bấy nhiêu mili-giây mới được đổi.
    ///
    /// ⚠️ VÌ SAO CẦN — lỗi PO gặp trên máy thật 12/09/2026: *"đã cầm máy dọc sẵn,
    /// máy báo là ảnh mẫu là ảnh dọc, cần xoay về"*.
    ///
    /// Cả hai nền tảng đều suy hướng từ gia tốc kế, tức từ **thành phần trọng lực
    /// nằm trong mặt phẳng màn hình**. Chúc máy xuống thì thành phần đó co lại gần
    /// bằng 0, và góc suy ra chỉ còn là nhiễu — nó nhảy sang ngang rồi về dọc liên
    /// tục.
    ///
    /// Mà app này **bảo người ta chúc máy xuống** (mục 3 và mục 4). Nghĩa là cảm
    /// biến hỏng đúng lúc app cần nó nhất.
    ///
    /// ⚠️ Hệ quả nếu bỏ qua không chỉ là một câu nhắc sai: [DeviceRotation] còn
    /// đặt góc quay cho luồng nhận diện. Lật nhầm là **toàn bộ khung xương xoay
    /// 90°** mà không có gì báo lỗi (FOOTGUNS 10).
    private static let GIU_HUONG_MS: Int64 = 400

    /// Cạnh DÀI của khung phân tích, pixel.
    ///
    /// Khớp mặc định `ImageAnalysis` của CameraX (640×480). Nhận diện trên 1080p
    /// thì trễ dồn, mà hướng dẫn trễ 1 giây tệ hơn hướng dẫn thưa.
    private static let PHAN_TICH_CANG_DAI = 640.0

    // -----------------------------------------------------------------
    // Thành phần
    // -----------------------------------------------------------------

    /// Khung xem trước. Màn chụp dựng `UIView` bọc lớp này — iOS không có
    /// `PreviewView` của CameraX.
    let previewLayer: AVCaptureVideoPreviewLayer

    private let detector: PoseDetector

    /// Camera đã mở xong. Tham số cho biết **nhận diện thời gian thực có chạy không**
    /// — máy yếu có thể không kham nổi cả ba chức năng cùng lúc, xem [configure].
    ///
    /// Phải là callback chứ không phải giá trị đọc ngay sau [start]: việc mở camera
    /// chạy bất đồng bộ, hỏi ngay sau khi gọi thì luôn nhận về kết quả của lần trước.
    private let onReady: (Bool) -> Void

    /// Hướng máy đổi. Gọi trên MainActor.
    private let onRotationChanged: (DeviceRotation) -> Void

    /// Báo ra ngoài khi có sự cố — không được im lặng (luật số 7 của dự án).
    private let onError: (String) -> Void

    private let session = AVCaptureSession()

    /// Dành riêng cho `startRunning()` / `stopRunning()`. Hai hàm này CHẶN tới khi
    /// camera thật sự mở/đóng xong (~0,3s) nên không được ném lung tung ra luồng
    /// giao diện, mà cũng không được chạy đồng thời với nhau.
    private let sessionQueue = DispatchQueue(label: "CaptureController.session")

    /// Luồng phân tích — tương đương `analysisExecutor` đơn luồng của Android.
    ///
    /// Đơn luồng là BẮT BUỘC: `PoseDetector.detect` giữ khoá trong lúc gửi khung
    /// đi, còn `stop()` phải chờ không còn khung nào đang dở thì người gọi mới được
    /// đóng bộ nhận diện (xem [stop]).
    private let frameQueue = DispatchQueue(label: "CaptureController.frame", qos: .userInitiated)

    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()

    private var frameRelay: FrameRelay?
    private let photoRelay = PhotoRelay()
    private let movieRelay = MovieRelay()

    private var activeDevice: AVCaptureDevice?

    /// Token trình nghe hướng máy, để gỡ đúng cặp với `addObserver`.
    private var orientationToken: NSObjectProtocol?

    private(set) var mode: Mode = .video

    /// Camera trước hay sau, và ảnh ghi ra có lật không. Đổi bằng [setShootMode].
    private(set) var shootMode: ShootMode = .NGUOI_KHAC

    /// Nhận diện thời gian thực có chạy được không. Xem [configure] để biết vì sao
    /// có thể không.
    private(set) var liveDetectionActive = false

    /// Video quay khung 16:9 hay 4:3. Khung chọn hẹp hơn 3:4 (9:16, Full) thì quay
    /// 16:9 để không mất độ phân giải; còn lại quay 4:3 để đủ phần hai bên.
    private var video169 = false

    private var currentRotation: DeviceRotation = .portrait
    private var huongChoDoi: DeviceRotation?
    private var huongChoTuTimeMs: Int64 = 0

    /// Đã [start] mà chưa [stop]. Các hàm đổi cấu hình phải bỏ qua khi chưa bật
    /// camera — bản Android cũng `return` sớm khi `cameraProvider == null`.
    private var started = false

    /// Danh sách ảnh chụp liên tục đang dở, kèm callback của lần gọi.
    private var burst: BurstJob?

    /// Callback báo khi quay xong — do [startRecording] để lại.
    private var recordingCompletion: ((URL?) -> Void)?

    private struct BurstJob {
        var dir: URL
        var count: Int
        var intervalMs: Int64
        /// Số tấm ĐANG chụp — dùng để đặt tên file, KHÔNG dùng `taken.count` vì
        /// tấm hỏng thì `taken.count` lùi lại và trùng tên với tấm đã ghi.
        var index: Int
        /// Tấm vừa bắn ra, chờ `PhotoRelay` báo về.
        var currentURL: URL?
        var taken: [URL]
        var onProgress: (Int) -> Void
        var onDone: ([URL]) -> Void
    }

    // -----------------------------------------------------------------
    // Khởi tạo
    // -----------------------------------------------------------------

    init(detector: PoseDetector,
         onReady: @escaping (Bool) -> Void,
         onRotationChanged: @escaping (DeviceRotation) -> Void,
         onError: @escaping (String) -> Void) {
        self.detector = detector
        self.onReady = onReady
        self.onRotationChanged = onRotationChanged
        self.onError = onError
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        // Khung xem trước FILL_CENTER — khớp `PreviewView` của CameraX và khớp
        // chỗ ghi trong tài liệu `TiLeKhung`.
        self.previewLayer.videoGravity = .resizeAspectFill
        photoRelay.owner = self
        movieRelay.owner = self
    }

    // -----------------------------------------------------------------
    // Bật / tắt
    // -----------------------------------------------------------------

    /// Mở camera. Bao gồm cả xin quyền — Android xin ở `MainActivity`, còn iOS
    /// không có chỗ nào trước màn chụp nên gộp vào đây cho gọn.
    func start() {
        guard !started else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if granted {
                            self.beginStart()
                        } else {
                            self.onError("Ứng dụng cần quyền camera để chụp ảnh và hướng dẫn.")
                        }
                    }
                }
            }
        default:
            onError("Camera đang bị tắt trong Cài đặt — bật quyền camera rồi thử lại.")
        }
    }

    private func beginStart() {
        guard !started else { return }
        started = true

        // Báo hướng ban đầu NGAY — trình nghe chỉ báo khi hướng ĐỔI, nên thiếu dòng
        // này thì bên nhận giữ nguyên hướng của lần chụp trước (lỗi 16/09/2026:
        // cầm dọc mà bị nhắc "xoay máy về dọc" suốt).
        currentRotation = Self.readInitialRotation()

        configure()

        // CHẠY phiên chụp. `configure()` mới chỉ GẮN input/output — không có
        // `startRunning()` thì không có buffer nào chạy, xem trước đen thui và
        // app báo "chưa có camera" dù quyền đã cấp (bản Android bật camera trong
        // `bindToLifecycle` nên chỗ này dễ quên khi port).
        //
        // ⚠️ PHẢI qua `sessionQueue`: `startRunning()` CHẶN tới khi phiên chạy
        // thật (mở ống kính, chiếm phần cứng) — gọi trên main là bảng đứng im
        // đúng lúc người dùng vừa bấm vào màn. Chỉ bắt đầu khi `configure()`
        // thành công (`activeDevice != nil`) — máy không có camera thì khỏi chạy.
        if activeDevice != nil {
            sessionQueue.async { [session] in
                if !session.isRunning {
                    session.startRunning()
                }
            }
        }

        applyRotation(currentRotation)   // cũng báo `onRotationChanged` lần đầu
        observeOrientation()
        onReady(liveDetectionActive)
    }

    /// Dừng camera.
    ///
    /// ⚠️ THỨ TỰ BẮT BUỘC, và phải CHỜ luồng phân tích dừng hẳn. Bên gọi sẽ đóng
    /// bộ nhận diện ngay sau hàm này; nếu còn một khung hình đang dở, nó sẽ gọi vào
    /// vùng nhớ vừa giải phóng và **sập ở tầng C++** (SIGSEGV) — không có thông báo
    /// lỗi nào, app chỉ tắt ngóm. Đã gặp thật khi xoay máy (FOOTGUNS mục 11).
    func stop() {
        guard started else { return }
        started = false

        stopObservingOrientation()

        // Quay dở thì dừng — kết quả vẫn về qua `recordingCompletion` do
        // `AVCaptureFileOutputRecordingDelegate` báo (giống `recording?.stop()`).
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        burst = nil

        // Gỡ delegate TRƯỚC, rồi chờ khung đang dở trong frameQueue xong — hai dòng
        // này là bản tương đương của `clearAnalyzer()` + `executor.shutdown()`.
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        frameQueue.sync { }

        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()

        sessionQueue.sync { [session] in
            if session.isRunning { session.stopRunning() }
        }

        activeDevice = nil
        frameRelay = nil
        liveDetectionActive = false
    }

    // -----------------------------------------------------------------
    // Dựng lại camera
    // -----------------------------------------------------------------

    /// Gắn lại TOÀN BỘ: input + output. Tương đương `bindAll()` của Android.
    ///
    /// Mọi lần đổi chế độ/chút tỉ lệ/lật camera đều đi qua đây, vì AVFoundation
    /// không cho thêm-bớt output "nóng" một cách an toàn khi session đang chạy.
    private func configure() {
        // Bước 0: cắt luồng phân tích cũ (nếu có) để không có khung nào rơi vào
        // giữa lúc tháo lắp.
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        frameQueue.sync { }

        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        // --- Camera ---
        guard let device = Self.cameraDevice(front: shootMode.camTruoc) else {
            session.commitConfiguration()
            onError("Máy này không tìm thấy camera.")
            return
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            onError("Không mở được camera: \(error.localizedDescription)")
            return
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            onError("Không gắn được camera vào phiên chụp.")
            return
        }
        session.addInput(input)
        activeDevice = device

        // Zoom về đúng tiêu cự gốc. CameraX trả về 1,0 mỗi lần `bindToLifecycle`,
        // còn `videoZoomFactor` sống trên chính `AVCaptureDevice` nên phải tự đặt lại.
        resetDeviceZoom(device)

        // --- Khung quay / khung chụp ---
        applySessionPreset()

        // --- Khung phân tích ---
        //
        // Bận thì VỨT khung mới, không xếp hàng. Xếp hàng gây trễ dồn — hướng dẫn
        // trễ 1 giây tệ hơn hướng dẫn thưa.
        videoOutput.alwaysDiscardsLateVideoFrames = true
        // Vision nhận `kCVPixelFormat_32BGRA`. Thu nhỏ luôn ở đây cho khớp mức
        // 640px của CameraX.
        let dims = analysisDims()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: dims.w,
            kCVPixelBufferHeightKey as String: dims.h,
        ]
        let relay = FrameRelay(detector: detector)
        relay.rotationDegrees = currentRotation.orientationDegrees
        videoOutput.setSampleBufferDelegate(relay, queue: frameQueue)
        frameRelay = relay

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            liveDetectionActive = true
        } else {
            // Không im lặng chạy thiếu (luật số 7): vẫn xem trước và ghi được, và
            // app sẽ chấm điểm sau khi ghi xong.
            liveDetectionActive = false
            onError("Máy này không chạy được nhận diện trong lúc quay. Vẫn quay được, và app sẽ chấm điểm sau khi quay xong.")
        }

        // ⚠️ Chụp liên tục và quay video không bật cùng lúc — xem [Mode]. CameraX
        // không cho cả bốn use case trên máy phổ thông, còn AVFoundation thì cho
        // nhưng ta GIỮ NGUYÊN ranh giới đó để hai đường chấm điểm không trộn vào nhau.
        if mode == .burst {
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            } else {
                onError("Không gắn được bộ chụp liên tục.")
            }
        } else {
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            } else {
                onError("Không gắn được bộ quay video.")
            }
        }

        // PHẢI commit trước khi đụng connection: `AVCaptureConnection` chỉ có sau
        // khi session hoàn tất cấu hình.
        session.commitConfiguration()

        applyMirroring()
    }

    /// Chọn preset/format cho session.
    ///
    /// ⚠️ Vì sao phải chọn ĐÚNG tỉ lệ chứ không phải cứ 1080p là xong:
    /// người dùng chọn khung 3:4 thì bản Android quay video **4:3** để vùng họ thấy
    /// trên màn hình nằm đủ trong video. Quay 16:9 rồi cắt 3:4 ra là mất đầu mất
    /// chân — đúng thứ mà cả dự án đang cố tránh.
    ///
    /// iOS không có preset 4:3 ở độ phân giải cao (chỉ có `.vga640x480`), nên
    /// dùng `inputPriority` + tự chọn `activeFormat`.
    private func applySessionPreset() {
        if mode == .burst {
            // Chụp liên tục là ảnh chụp thật full độ phân giải — `.photo` cho đúng
            // cảm biến, không phải khung video.
            if session.canSetSessionPreset(.photo) {
                session.sessionPreset = .photo
                return
            }
        } else if applyActiveFormat(video169: video169) {
            return
        }

        // Đường lui: 1080p. Quay được ở chất lượng thấp vẫn hơn không quay được.
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }
    }

    /// Đặt `activeFormat` có tỉ lệ đúng và độ phân giải gần Full HD nhất.
    /// - Returns: `false` = máy không có format đúng tỉ lệ, người gọi lo đường lui.
    private func applyActiveFormat(video169: Bool) -> Bool {
        guard let device = activeDevice,
              let chosen = Self.bestFormat(on: device, aspect: video169 ? 16.0 / 9.0 : 4.0 / 3.0)
        else { return false }

        guard session.canSetSessionPreset(.inputPriority) else { return false }
        session.sessionPreset = .inputPriority

        do {
            try device.lockForConfiguration()
            device.activeFormat = chosen
            // 30 khung/giây — đủ cho hướng dẫn và nhẹ hơn 60 cho bộ nhận diện.
            // frameDuration = THỜI GIAN / khung, nên 30fps là 1/30 giây:
            // CMTime(value: 1, timescale: 30). Viết 30/1 nghĩa là 30 GIÂY/khung
            // (0.03 fps) → AVFoundation ném exception NGOÀI Swift do/catch → treo máy.
            if chosen.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
                let duration = CMTime(value: 1, timescale: 30)
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }
            device.unlockForConfiguration()
            return true
        } catch {
            device.unlockForConfiguration()
            return false
        }
    }

    /// Kích thước khung phân tích: cạnh dài = [PHAN_TICH_CANG_DAI], GIỮ NGUYÊN tỉ
    /// lệ của cảm biến.
    ///
    /// ⚠️ Tỉ lệ phải khớp CHÍNH XÁC. `videoSettings` ép buffer về đúng W×H đã ghi;
    /// nếu tỉ lệ lệch thì AVFoundation cắt xén — mà cắt xén là đổi vùng đo, và mọi
    /// tiêu chí sau đó đều sai âm thầm.
    private func analysisDims() -> (w: Int, h: Int) {
        guard let device = activeDevice else { return (640, 480) }
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        guard dims.width > 0, dims.height > 0 else { return (640, 480) }

        // Khung cảm biến LUÔN ngang tại thời điểm tới delegate (chưa ai xoay nó).
        let w0 = Double(max(dims.width, dims.height))
        let h0 = Double(min(dims.width, dims.height))
        let w = Int((Self.PHAN_TICH_CANG_DAI).rounded())
        var h = Int((Double(w) * h0 / w0).rounded())
        if h < 2 { h = 2 }
        return (w & ~1, h & ~1)   // ép chẵn để bộ chuyển đổi không phàn nàn
    }

    // -----------------------------------------------------------------
    // Đổi cấu hình từ người dùng
    // -----------------------------------------------------------------

    /// Đổi cách bắt ảnh. Phải dựng lại camera vì hai chế độ dùng hai bộ output
    /// khác nhau (xem [Mode]).
    func setMode(_ next: Mode) {
        if next == mode { return }
        mode = next
        guard started else { return }
        configure()
        applyRotation(currentRotation)
    }

    /// Đổi camera trước/sau, hoặc đổi cách người ta cầm máy (ảnh có lật không).
    ///
    /// ⚠️ Chỉ dựng lại khi ĐỔI CAMERA. Đổi `ShootMode` giữa hai kiểu tự chụp thì
    /// ống kính vẫn là ống đó, chỉ câu chữ và việc lật khung xương đổi — dựng lại
    /// là vô ích mà còn reset zoom của người dùng.
    func setShootMode(_ next: ShootMode) {
        if next == shootMode { return }
        let doiCamera = next.camTruoc != shootMode.camTruoc
        shootMode = next
        guard doiCamera, started else { return }
        configure()
        applyRotation(currentRotation)
    }

    /// Người dùng đổi tỉ lệ khung. Chỉ dựng lại camera khi phải đổi khung quay video.
    func setTiLeKhung(_ tiLeDoc: Double) {
        let next = tiLeDoc < Self.TI_LE_4_3_DOC - 0.02
        if next == video169 { return }
        video169 = next
        guard started else { return }
        configure()
        applyRotation(currentRotation)
    }

    // -----------------------------------------------------------------
    // Zoom
    // -----------------------------------------------------------------

    /// Mức zoom hiện tại. 1,0 = không zoom (đúng tiêu cự gốc của ống kính).
    ///
    /// ⚠️ Vì sao phải theo dõi zoom: khung xem trước iOS có cử chỉ chụm hai ngón
    /// (lớp `AVCaptureVideoPreviewLayer` không tự có, nhưng màn chụp thêm vào). Mục
    /// xa/gần đo bằng **kích thước mẫu trong khung**, nên zoom vào thì mục đó ĐẠT
    /// dù người vẫn đứng nguyên chỗ cũ — qua được tiêu chí mà không cần bước chân
    /// nào. Đây là một **đường lách qua tiêu chí**, không phải tính năng thiếu.
    var zoomRatio: Float {
        guard let device = activeDevice else { return 1 }
        return Float(device.videoZoomFactor)
    }

    /// Đưa zoom về đúng tiêu cự gốc. Gọi khi người dùng bấm nút sửa cảnh báo zoom.
    func resetZoom() { setZoom(1) }

    /// Đặt mức zoom. Tự kẹp vào khoảng máy này làm được, nên gọi 3x trên máy chỉ
    /// hỗ trợ tới 2x thì được 2x chứ không lỗi.
    func setZoom(_ ratio: Float) {
        guard let device = activeDevice else { return }
        let lo = device.minAvailableVideoZoomFactor
        let hi = device.maxAvailableVideoZoomFactor
        let target = min(max(CGFloat(ratio), lo), hi)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = target
            device.unlockForConfiguration()
        } catch {
            // Không báo lỗi ra ngoài: đặt zoom thất bại không phá gì cả, chỉ là
            // người dùng bấm không ăn.
        }
    }

    /// CÁC MỨC ZOOM MÁY NÀY LÀM ĐƯỢC, để dựng nút bấm.
    ///
    /// Không viết cứng 1x/2x/3x: máy rẻ tiền chỉ tới 4x, máy có ống tele lên tới
    /// 10x, máy không có ống góc rộng thì không xuống được 0,5x. Viết cứng thì nút
    /// bấm vào không có tác dụng mà người dùng không hiểu vì sao.
    func zoomStops() -> [Float] {
        guard let device = activeDevice else { return [1] }
        let lo = Float(device.minAvailableVideoZoomFactor)
        let hi = Float(device.maxAvailableVideoZoomFactor)
        var out: [Float] = []
        if lo <= 0.6 { out.append(0.5) }
        if lo <= 1, 1 <= hi { out.append(1) }
        for z: Float in [2, 3, 5, 10] where z <= hi { out.append(z) }
        return out
    }

    /// KHOẢNG ZOOM LIÊN TỤC máy này làm được — dùng cho thao tác kéo thả.
    ///
    /// [zoomStops] chỉ cho vài mức tròn để bấm nhanh; muốn kéo mượt qua 1,3x hay
    /// 2,7x thì phải biết hai đầu mút thật.
    func zoomRange() -> ClosedRange<Float> {
        guard let device = activeDevice else { return 1...1 }
        return Float(device.minAvailableVideoZoomFactor)...Float(device.maxAvailableVideoZoomFactor)
    }

    private func resetDeviceZoom(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            let lo = device.minAvailableVideoZoomFactor
            if device.videoZoomFactor != 1, lo <= 1 {
                device.videoZoomFactor = 1
            }
            device.unlockForConfiguration()
        } catch {
            // Bỏ qua — zoom giữ nguyên cũng không sao.
        }
    }

    // -----------------------------------------------------------------
    // Góc mở dọc
    // -----------------------------------------------------------------

    /// GÓC MỞ DỌC CỦA ỐNG KÍNH ở mức zoom hiện tại, tính bằng ĐỘ.
    ///
    /// Mục 3 (máy cao/thấp) cần con số này:
    ///
    ///     elevation = độ_nghiêng_máy + (0,5 − y_mốc) × vFOV
    ///
    /// Bản Android đọc từ Camera2: `vFOV = 2·atan(cao_cảm_biến / (2·tiêu_cự))`.
    /// iOS không khai `SENSOR_INFO_PHYSICAL_SIZE` + `LENS_INFO_AVAILABLE_FOCAL_LENGTHS`,
    /// nhưng `AVCaptureDevice.Format.videoFieldOfView` cho **góc ngang của chính
    /// cảm biến** (tính ở zoom = 1, không đổi theo `videoZoomFactor` — nó là tài
    /// sản của format, zoom chỉ cắt thêm ở giữa). Mà
    ///
    ///     tan(nửa_góc_độ_dài) = (canh_dài / 2) / tiêu_cự
    ///                           = tan(hFOV / 2)
    ///
    /// nên chỉ cần thay thế trực tiếp, giữ nguyên mọi bước sau của công thức gốc.
    ///
    /// ⚠️ **Zoom** thu hẹp góc nhìn thật: `tan(vFOV'/2) = tan(vFOV/2) / zoom`.
    ///
    /// ⚠️ **Tỉ lệ khung** người dùng chọn (`TiLeKhung`): tầng đo đọc `y` trong khung
    /// ĐÃ CẮT, nên vFOV phải là của khung đã cắt. Khung rộng hơn cảm biến (1:1) thì
    /// cắt trên dưới — vFOV hẹp lại; khung hẹp hơn (9:16) thì cắt hai bên — giữ nguyên.
    ///
    /// Trả `nil` khi chưa gắn camera; lúc đó tầng đo lùi về `Measurer.VFOV_ANH_MAU`.
    func verticalFovDeg(tiLeKhung: Double?) -> Double? {
        guard let device = activeDevice else { return nil }
        let format = device.activeFormat
        let hFov = Double(format.videoFieldOfView)
        guard hFov > 0 else { return nil }
        let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        guard d.width > 0, d.height > 0 else { return nil }

        // Cảm biến khai báo theo chiều NGANG của máy; app chụp dọc nên cạnh
        // "dọc trên màn hình" là cạnh DÀI của cảm biến.
        let canhDoc = Double(max(d.width, d.height))
        let canhNgang = Double(min(d.width, d.height))

        // Nửa-tan theo CHIỀU DÀI lấy thẳng từ hFOV — không cần chiều dài vật lý
        // hay tiêu cự (iOS không khai hai thông số đó cho video).
        var nuaTan = tan(hFov * .pi / 180.0 / 2.0)
        nuaTan /= max(Double(zoomRatio), 0.01)
        let tiLeCamBien = canhNgang / canhDoc
        if let tiLeKhung, tiLeKhung > tiLeCamBien {
            nuaTan *= tiLeCamBien / tiLeKhung
        }
        return 2.0 * atan(nuaTan) * 180.0 / .pi
    }

    // -----------------------------------------------------------------
    // Hướng máy
    // -----------------------------------------------------------------

    private func observeOrientation() {
        guard orientationToken == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationToken = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDeviceOrientationChanged()
            }
        }
    }

    private func stopObservingOrientation() {
        if let token = orientationToken {
            NotificationCenter.default.removeObserver(token)
            orientationToken = nil
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        huongChoDoi = nil
    }

    private func handleDeviceOrientationChanged() {
        guard let next = DeviceRotation.from(deviceOrientation: UIDevice.current.orientation) else {
            // faceUp / faceDown / unknown — Android cũng bỏ qua `ORIENTATION_UNKNOWN`.
            return
        }
        if next == currentRotation {
            huongChoDoi = nil
            return
        }
        // Hướng mới: bắt đầu đếm giờ, chưa đổi ngay.
        let now = Self.uptimeMs()
        if next != huongChoDoi {
            huongChoDoi = next
            huongChoTuTimeMs = now
            return
        }
        if now - huongChoTuTimeMs < Self.GIU_HUONG_MS { return }
        huongChoDoi = nil
        applyRotation(next)
    }

    /// Áp hướng mới cho MỌI connection đang mở.
    ///
    /// ⚠️ Thiếu dòng này thì khung đưa vào bộ nhận diện bị nghiêng 90° khi cầm ngang
    /// — app chạy bình thường, không báo lỗi, chỉ có hướng dẫn sai (FOOTGUNS mục 10).
    /// Chỗ tương đương của `imageAnalysis.targetRotation` / `videoCapture.targetRotation`
    /// / `imageCapture.targetRotation` của Android gộp lại thành một hàm duy nhất,
    /// vì AVFoundation có một `AVCaptureConnection` cho mỗi output.
    private func applyRotation(_ rotation: DeviceRotation) {
        currentRotation = rotation

        // Khung xem trước: AVFoundation tự xoay buffer, đúng mọi chiều máy.
        if let conn = previewLayer.connection, conn.isVideoRotationAngleSupported(rotation.videoRotationAngle) {
            conn.videoRotationAngle = rotation.videoRotationAngle
        }

        // ⚠️ Khung phân tích thì NGƯỢC lại: KHÔNG xoay ở connection. Buffer giữ
        // nguyên chiều cảm biến, còn phép xoay giao cho MediaPipe qua
        // `orientationDegrees` — đúng như cách `ImageProxy` của CameraX làm. Xoay
        // ở cả hai chỗ là xoay hai lần.
        frameRelay?.rotationDegrees = rotation.orientationDegrees

        // Ảnh chụp liên tục: AVFoundation ghi hướng vào EXIF (không xoay pixel),
        // người đọc ảnh tự xoay theo — bản Android `targetRotation` cũng vậy.
        if let conn = photoOutput.connection(with: .video),
           conn.isVideoRotationAngleSupported(rotation.videoRotationAngle) {
            conn.videoRotationAngle = rotation.videoRotationAngle
        }

        // Video: AVFoundation gắn track transform cho video track, phim chạy ra
        // đúng chiều mà không tốn một phép xoay pixel nào.
        if let conn = movieOutput.connection(with: .video),
           conn.isVideoRotationAngleSupported(rotation.videoRotationAngle) {
            conn.videoRotationAngle = rotation.videoRotationAngle
        }

        onRotationChanged(rotation)
    }

    private func applyMirroring() {
        // ⚠️ Khung phân tích KHÔNG được lật. Bản Android để `ImageAnalysis` nguyên
        // rồi `CaptureViewModel` tự lật khung xương (`rawFrame.mirrored()`), vì
        // ảnh lật làm bộ nhận diện gọi tay PHẢI thật là `LEFT_WRIST`. Lật sớm hơn
        // là lật hai lần.
        if let conn = videoOutput.connection(with: .video), conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = false
        }

        // Ảnh/video GHI RA thì lật đúng khi camera trước:
        // `latGuong && camTruoc` của bản Android — quyết định sản phẩm 06/09/2026:
        // *người dùng nhìn màn hình thế nào thì muốn ảnh ra thế đó*.
        let mirror = shootMode.camTruoc
        if let conn = movieOutput.connection(with: .video), conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = mirror
        }
        if let conn = photoOutput.connection(with: .video), conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = mirror
        }

        // Khung xem trước thì để mặc định: `AVCaptureVideoPreviewLayer` tự lật
        // camera trước (chuẩn soi gương, ai cũng quen) — khớp `PreviewView` của
        // CameraX.
    }

    /// Hướng ban đầu: đọc theo `UIDevice`, thiếu thì theo hướng giao diện, vẫn
    /// không được thì coi như dọc (bản Android mặc định `Surface.ROTATION_0`).
    private static func readInitialRotation() -> DeviceRotation {
        if let r = DeviceRotation.from(deviceOrientation: UIDevice.current.orientation) {
            return r
        }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        if let o = scene.flatMap({ DeviceRotation.from(interfaceOrientation: $0.interfaceOrientation) }) {
            return o
        }
        return .portrait
    }

    // -----------------------------------------------------------------
    // Chụp liên tục
    // -----------------------------------------------------------------

    /// Chụp một loạt [count] ảnh, cách nhau [intervalMs].
    ///
    /// ⚠️ Chụp NỐI TIẾP chứ không bắn cùng lúc: mỗi lần chụp chiếm ống kính và bộ
    /// xử lý ảnh của máy. Bắn chồng lên nhau thì máy tự huỷ bớt, kết quả là số ảnh
    /// nhận về ít hơn số đã hứa mà không có lỗi nào báo ra.
    ///
    /// - Parameter onProgress số ảnh đã chụp xong, để vẽ thanh tiến trình
    /// - Parameter onDone danh sách file thật sự chụp được — có thể ít hơn [count]
    func captureBurst(dir: URL,
                      count: Int,
                      intervalMs: Int64,
                      onProgress: @escaping (Int) -> Void,
                      onDone: @escaping ([URL]) -> Void) {
        guard mode == .burst, burst == nil, session.outputs.contains(photoOutput) else {
            onError("Chưa bật được chế độ chụp liên tục.")
            onDone([])
            return
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            onError("Không tạo được thư mục ảnh: \(error.localizedDescription)")
            onDone([])
            return
        }
        burst = BurstJob(dir: dir, count: count, intervalMs: intervalMs,
                         index: 0, currentURL: nil, taken: [],
                         onProgress: onProgress, onDone: onDone)
        shootNextBurst()
    }

    private func shootNextBurst() {
        guard var job = burst else { return }
        if job.index >= job.count {
            finishBurst()
            return
        }
        // Cùng tên như bản Android — xếp được theo thứ tự chỉ bằng tên file.
        let url = job.dir.appendingPathComponent(String(format: "burst-%02d.jpg", job.index))
        job.index += 1
        job.currentURL = url
        burst = job

        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        } else {
            settings = AVCapturePhotoSettings()
        }
        photoOutput.capturePhoto(with: settings, delegate: photoRelay)
    }

    /// Gọi từ `PhotoRelay` khi một tấm về — hoặc về với lỗi.
    fileprivate func onBurstPhoto(photo: AVCapturePhoto, error: Error?) {
        guard burst != nil else { return }
        if let error {
            // Hỏng một tấm thì bỏ qua tấm đó, KHÔNG bỏ cả loạt.
            NSLog("CaptureController: Chụp hỏng một tấm — \(error)")
        } else if let url = burst?.currentURL, let data = photo.fileDataRepresentation() {
            do {
                try data.write(to: url, options: .atomic)
                burst?.taken.append(url)
            } catch {
                NSLog("CaptureController: Không ghi được ảnh — \(error)")
            }
        }
        burst?.currentURL = nil
        burst?.onProgress(burst?.taken.count ?? 0)

        // Hẹn nhịp bằng chính luồng giao diện: không cần thêm luồng nào, và tự
        // dừng khi người dùng rời màn hình (`burst = nil` trong `stop()`).
        let intervalMs = burst?.intervalMs ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(intervalMs))) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.burst != nil else { return }
                self.shootNextBurst()
            }
        }
    }

    private func finishBurst() {
        guard let job = burst else { return }
        burst = nil
        job.onDone(job.taken)
    }

    // -----------------------------------------------------------------
    // Quay video
    // -----------------------------------------------------------------

    var isRecording: Bool { movieOutput.isRecording }

    /// Bắt đầu quay vào [outputFile].
    ///
    /// KHÔNG thu tiếng — sản phẩm không dùng tới, mà xin quyền micro sẽ làm người
    /// dùng nghi ngờ vô cớ ở một app chụp ảnh.
    ///
    /// - Parameter onFinished gọi khi quay xong. `nil` nghĩa là quay hỏng.
    func startRecording(outputFile: URL, onFinished: @escaping (URL?) -> Void) {
        guard mode == .video, session.outputs.contains(movieOutput) else {
            onError("Camera chưa sẵn sàng để quay")
            onFinished(nil)
            return
        }
        guard !movieOutput.isRecording else { return }
        recordingCompletion = onFinished
        movieOutput.startRecording(to: outputFile, recordingDelegate: movieRelay)
    }

    /// Dừng quay. Kết quả trả về qua `onFinished` đã truyền lúc bắt đầu.
    func stopRecording() {
        if movieOutput.isRecording { movieOutput.stopRecording() }
    }

    /// Gọi từ `MovieRelay`.
    fileprivate func onRecordingFinished(url: URL, error: Error?) {
        let done = recordingCompletion
        recordingCompletion = nil

        if let error = error as NSError? {
            // AVFoundation hay báo lỗi VỚI ảnh vẫn ghi được (bị ngắt giữa chừng
            // nhưng đoạn đã có đủ). Phải đọc khoá này, không thì vứt phim đi oan.
            let thanhCong = (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
            if !thanhCong {
                onError("Quay video hỏng (\(error.localizedDescription)). Thử lại được.")
                try? FileManager.default.removeItem(at: url)
                done?(nil)
                return
            }
        }
        done?(url)
    }

    // -----------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------

    private static func cameraDevice(front: Bool) -> AVCaptureDevice? {
        // ⚠️ CHỌN RÕ ống wide (`1x`), KHÔNG lấy `AVCaptureDevice.default(for: .video)`.
        //
        // Máy ống kép/ba ống trả về "virtual device" mà `videoZoomFactor = 1` của nó
        // không tương ứng 1x như bản Android — mà `DistanceEstimator` đang suy
        // khoảng cách bằng chính con số đó (`d = C × zoom × H / s`, hiệu chuẩn ở
        // 1,0x). Chọn sai ống là SỐ BƯỚC CHÂN sai mà không có lỗi nào báo.
        let position: AVCaptureDevice.Position = front ? .front : .back
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    /// Format có tỉ lệ đúng và độ phân giải gần Full HD nhất.
    private static func bestFormat(on device: AVCaptureDevice, aspect: Double) -> AVCaptureDevice.Format? {
        let targetArea = 1920.0 * 1080.0
        var best: AVCaptureDevice.Format?
        var bestScore = Double.greatestFiniteMagnitude
        for format in device.formats {
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard d.width > 0, d.height > 0, d.width >= d.height else { continue }
            let w = Double(d.width)
            let h = Double(d.height)
            let a = w / h
            // Tỉ lệ phải khớp trong 3%, nếu không thì khung quay và khung xem
            // trước lệch nhau — người dùng canh một khung, nhận về khung khác.
            let aspectErr = abs(a - aspect) / aspect
            guard aspectErr <= 0.03 else { continue }
            let score = aspectErr * 10.0 + abs(w * h - targetArea) / targetArea
            if score < bestScore {
                bestScore = score
                best = format
            }
        }
        return best
    }

    /// `SystemClock.uptimeMillis()` của Android.
    private static func uptimeMs() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }
}

// =========================================================================
// Lớp trung gian cho delegate
//
// ⚠️ PHẢI `nonisolated`. Theo mặc định mọi thứ trong file này là MainActor, mà
// delegate của AVFoundation gọi trên luồng riêng — ghi vào trạng thái MainActor
// từ đó là data race. Ba lớp dưới đây không giữ gì của MainActor, chỉ chuyển
// việc về đúng luồng.
// =========================================================================

/// Khung hình tới → đưa ngay vào bộ nhận diện. Tương đương lambda
/// `a.setAnalyzer(executor) { imageProxy -> ... }` của Android.
private nonisolated final class FrameRelay: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    private let detector: PoseDetector
    private let lock = NSLock()
    private var _rotationDegrees = 90

    init(detector: PoseDetector) {
        self.detector = detector
    }

    /// Góc truyền cho `PoseDetector` — do `CaptureController` cập nhật mỗi khi
    /// hướng máy đổi. Đọc/ghi qua khoá vì viết ở MainActor, đọc ở luồng khung hình.
    var rotationDegrees: Int {
        get { lock.lock(); defer { lock.unlock() }; return _rotationDegrees }
        set { lock.lock(); _rotationDegrees = newValue; lock.unlock() }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // KHÔNG dispatch về MainActor ở đây — Android cũng vậy. Việc nặng dừng ở
        // đúng luồng khung hình, kết quả về sau qua callback của `PoseDetector`.
        detector.detect(pixelBuffer: pixelBuffer, orientationDegrees: rotationDegrees)
    }
}

/// Một tấm chụp liên tục xong → giao về `CaptureController` trên MainActor.
private nonisolated final class PhotoRelay: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    weak var owner: CaptureController?

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        Task { @MainActor in
            self.owner?.onBurstPhoto(photo: photo, error: error)
        }
    }
}

/// Quay xong → giao về `CaptureController` trên MainActor.
private nonisolated final class MovieRelay: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    weak var owner: CaptureController?

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        Task { @MainActor in
            self.owner?.onRecordingFinished(url: outputFileURL, error: error)
        }
    }
}
