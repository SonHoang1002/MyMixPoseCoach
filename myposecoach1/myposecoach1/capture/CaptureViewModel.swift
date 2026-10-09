import Combine
import Foundation
import UIKit

/// Giữ trạng thái màn chụp thật.
///
/// Không giữ Context, camera hay bộ nhận diện — những thứ đó gắn với vòng đời màn
/// hình và do tầng giao diện quản lý.
///
/// Port 1:1 từ `CaptureViewModel.kt` của Android — giữ nguyên tên hàm, thứ tự phép
/// tính và chuỗi thông báo để còn đối chiếu được khi kết quả sai.
@MainActor
final class CaptureViewModel: ObservableObject {

    @Published var state = CaptureUiState()

    /// Số đo ẢNH MẪU và lớp khung hình của nó.
    ///
    /// ⚠️ Chốt MỘT LẦN ở đây rồi dùng lại cho mọi khung hình về sau. Không bao giờ
    /// suy lại từ camera — đó là "nguyên nhân thứ 8", đã có số liệu chứng minh lớp
    /// khung hình nhảy KNEE↔FULL dù người đứng yên.
    private(set) var templateProfile: TemplateProfile? = nil

    /// ENGINE HƯỚNG DẪN. Tạo MỘT LẦN khi phân tích xong ảnh mẫu, vì nó giữ trạng
    /// thái khoá/mở của từng tiêu chí qua nhiều khung hình.
    private var engine: GuidanceEngine? = nil

    /// Khung xương thô của ẢNH MẪU — giữ lại để viết câu nhắc chỉnh dáng theo khớp.
    private var templateFrameForPose: PoseFrame? = nil

    /// Hai giá trị mới nhất từ bên ngoài vòng đo.
    private var angularSpeedDegPerSec: Double = 0.0
    private var deviceRollDeg: Double? = nil
    private var devicePitchDeg: Double? = nil
    private var devicePortrait = true

    /// Tỉ lệ khung người dùng chọn. `nil` = chưa biết, đo trên toàn khung.
    private(set) var tiLeKhung: Double? = nil

    func onTiLeKhungChanged(_ tiLe: Double) {
        tiLeKhung = tiLe
    }

    /// Mức zoom nhỏ nhất máy làm được — đọc một lần khi camera sẵn sàng.
    private var zoomMin: Float = 0.5

    func onZoomMin(_ min: Float) {
        zoomMin = min
    }

    private var zoomRatio: Float = 1

    /// Góc mở DỌC của ống kính ở mức zoom và tỉ lệ khung hiện tại, độ.
    /// `null` = chưa đọc được, tầng đo lùi về `Measurer.VFOV_ANH_MAU`.
    private var vFovDeg: Double? = nil

    /// Số liệu khuôn mặt mới nhất kèm mốc thời gian. Nhận diện khuôn mặt chạy THƯA
    /// hơn nhịp khung hình, nên giữ giá trị gần nhất; quá cũ thì bỏ.
    private var liveFace: FaceInfo? = nil
    private var liveFaceAtMs: Int64 = 0

    /// Số liệu khuôn mặt cũ hơn mức này thì coi như không có.
    private let FACE_TOI_DA_MS: Int64 = 600

    /// Chế độ chụp. iOS chỉ dùng camera SAU nên `mode.camTruoc` luôn false — nút
    /// lật camera không có trên iOS; `TU_CHUP_CAM_TRUOC` để dành cho tương lai.
    private(set) var mode: ShootMode = .NGUOI_KHAC

    /// Sẵn sàng quay chưa: phải có ảnh mẫu đo được VÀ camera mở được.
    var readyToRecord: Bool {
        templateProfile != nil && state.cameraReady
    }

    /// XOÁ SẠCH DẤU VẾT LẦN TRƯỚC — gọi mỗi lần vào lại màn hình.
    func startFresh() {
        templateProfile = nil
        engine = nil
        templateFrameForPose = nil
        angularSpeedDegPerSec = 0.0
        deviceRollDeg = nil
        devicePitchDeg = nil
        zoomRatio = 1
        vFovDeg = nil
        liveFace = nil
        liveFaceAtMs = 0
        // ⚠️ HƯỚNG MÁY PHẢI VỀ MẶC ĐỊNH. Bản trước quên dòng này: lần chụp trước
        // cảm biến lỡ nhảy sang "ngang" thì lần sau mở màn chụp vẫn bị nhắc "xoay
        // máy về dọc" mãi — màn chụp mới không báo lại hướng khi hướng không đổi.
        devicePortrait = true
        // ⚠️ GIỮ LẠI hai lựa chọn của người dùng: chế độ chụp và tỉ lệ khung.
        state = CaptureUiState(mode: mode)
    }

    /// Cảm biến nghiêng bảo vệ. Gọi ~30 lần/giây từ màn hình.
    func onSensorReading(angularSpeed: Double, rollDeg: Double? = nil, pitchDeg: Double? = nil) {
        angularSpeedDegPerSec = angularSpeed
        deviceRollDeg = rollDeg
        devicePitchDeg = pitchDeg
    }

    /// Hướng cầm máy đổi. Gọi từ callback của CaptureController.
    func onRotationChanged(portrait: Bool) {
        devicePortrait = portrait
        state.devicePortrait = portrait
    }

    /// Bật/tắt chế độ tự bấm. KHÁC HẲN `onModeChanged(burst)` — cái đó chọn quay
    /// video hay chụp liên tục, cái này chọn AI cầm máy.
    func onAutoModeChanged(_ on: Bool) {
        state.autoMode = on
        state.countdown = nil
    }

    func onCountdown(_ sec: Int?) {
        state.countdown = sec
    }

    func onShootModeChanged(_ cheDo: ShootMode) {
        mode = cheDo
        state.mode = cheDo
    }

    /// Màn chụp đẩy góc mở ống kính đọc từ phần cứng vào.
    func onVerticalFovChanged(_ deg: Double?) {
        vFovDeg = deg
    }

    /// Màn chụp đẩy số liệu khuôn mặt vừa nhận diện được vào.
    func onLiveFace(_ info: FaceInfo?) {
        liveFace = info
        liveFaceAtMs = Self.monotonicMs()
    }

    func onZoomChanged(_ ratio: Float) {
        // Gọi ~30 lần/giây từ vòng cảm biến. `@Published` KHÔNG tự so sánh giá
        // trị: gán đúng một giá trị cũ cũng bắn objectWillChange → cả cây view
        // ~1000 dòng dựng lại 30 lần mỗi giây → màn hình "đơ" dù không có gì đổi.
        // Chỉ ghi khi zoom THẬT SỰ đổi (người dùng kéo/ngắm).
        guard ratio != zoomRatio || ratio != state.zoomRatio else { return }
        zoomRatio = ratio
        state.zoomRatio = ratio
    }

    // -----------------------------------------------------------------
    // Ảnh mẫu
    // -----------------------------------------------------------------

    func onTemplateAnalyzed(
        name: String,
        thumb: UIImage?,
        frame: PoseFrame?,
        minVisibility: Float,
        face: FaceInfo? = nil
    ) {
        if frame == nil || frame!.isEmpty {
            state.templateName = name
            state.templateThumb = thumb
            state.analyzingTemplate = false
            state.templateError = frame == nil
                ? "Không nạp được model để phân tích ảnh mẫu"
                : "Không tìm thấy người trong ảnh mẫu"
            return
        }
        let khung = frame!
        let framing = FramingClass.detect(khung, minVisibility: minVisibility)
        if framing == nil {
            state.templateName = name
            state.templateThumb = thumb
            state.analyzingTemplate = false
            state.templateError = "Không xác định được kiểu khung hình của ảnh mẫu"
            return
        }
        // ⚠️ HỒ SƠ ẢNH MẪU chốt Ở ĐÂY, một lần duy nhất. Nó quyết định luôn những
        // tiêu chí nào được chấm cho ảnh mẫu này.
        let profile = TemplateProfile.from(
            khung, framing: framing!, minVisibility: minVisibility, face: face,
            gocMayNhan: MediaLibrary.gocMayTheoNhan(name),
            kieuChupTren: MediaLibrary.kieuChupTrenTheoNhan(name)
        )
        templateProfile = profile
        // Engine phải tạo SAU khi có hồ sơ, vì nó đọc hồ sơ để biết mục nào áp dụng.
        engine = GuidanceEngine(profile: profile)
        templateFrameForPose = khung

        // Ảnh mẫu dọc hay ngang — quyết định việc nhắc người dùng xoay máy.
        let portrait = thumb.map { Int($0.size.height) >= Int($0.size.width) }

        state.templateName = name
        state.templateThumb = thumb
        state.templateFraming = framing
        state.criteriaSummary = profile.describe()
        state.templatePortrait = portrait
        state.analyzingTemplate = false
        state.templateError = nil
    }

    // -----------------------------------------------------------------
    // Camera
    // -----------------------------------------------------------------

    func onCameraReady(_ liveDetectionActive: Bool) {
        state.cameraReady = true
        state.liveDetectionActive = liveDetectionActive
    }

    func onCameraError(_ message: String) {
        state.cameraError = message
    }

    /// Một khung hình vừa nhận diện xong. Gọi từ luồng nền của Vision.
    func onLiveFrame(rawFrame: PoseFrame, stats: PoseDetector.InferenceStats, minVisibility: Float) {
        // ⚠️ CAMERA TRƯỚC: khung do bộ nhận diện nhận được là ảnh THÔ TỪ CẢM BIẾN
        // (chưa lật), trong khi khung xem trước đã bị lật. iOS không có camera
        // trước nên nhánh này không chạy, nhưng giữ để 1:1 với Android.
        let khungLat = mode.camTruoc ? rawFrame.mirrored() : rawFrame
        // Cắt về tỉ lệ khung người dùng chọn — đúng vùng họ đang thấy trên màn hình
        // và đúng vùng ảnh ra. Xem `TiLeKhung`.
        let rong = stats.inputWidth
        let cao = stats.inputHeight
        let tl = tiLeKhung.flatMap {
            rong > 0 && cao > 0 ? TiLeKhung.theoHuong($0, rong: rong, cao: cao) : nil
        }
        let frame: PoseFrame
        if let tl {
            frame = khungLat.croppedToAspect(targetAspect: tl, frameAspect: Double(rong) / Double(cao))
        } else {
            frame = khungLat
        }
        let rongCat: Int
        let caoCat: Int
        if let tl {
            if tl < Double(rong) / Double(cao) {
                rongCat = Int(Double(cao) * tl)
                caoCat = cao
            } else {
                rongCat = rong
                caoCat = Int(Double(rong) / tl)
            }
        } else {
            rongCat = rong
            caoCat = cao
        }
        let detected = !frame.isEmpty && frame.visibility.contains { $0 >= minVisibility }
        let profile = templateProfile
        let eng = engine

        // ⚠️ CẦM MÁY SAI thì mọi phép đo phía sau đều mất nghĩa — xét TRƯỚC 6 tiêu chí.
        let prep = CameraPrep.warningFor(
            devicePortrait: devicePortrait,
            templatePortrait: state.templatePortrait,
            zoomRatio: zoomRatio
        )

        // ⚠️ DÙNG CHÍNH `Measurer.measure` mà ảnh mẫu đã đi qua, với ĐÚNG lớp khung
        // hình của ảnh mẫu. Đây là bất biến số 1 của dự án: hướng dẫn realtime và
        // chấm điểm sau khi quay phải đọc từ cùng một phép đo.
        // Góc máy SUY TỪ ẢNH của chính khung camera — chỉ để hiện cạnh số cảm biến,
        // không dùng để chấm.
        var gocAnhLive: Double? = nil
        let live: PoseMeasurement?
        if detected, let profile {
            let vFov = vFovDeg ?? Measurer.VFOV_ANH_MAU
            // Số liệu khuôn mặt cũ quá ngưỡng thì bỏ. iOS luôn nil (không có ML Kit
            // Face trên iOS), nhưng giữ nhánh đủ độ để 1:1 với Android.
            let freshFace = liveFace.flatMap { info -> FaceInfo? in
                guard Self.monotonicMs() - liveFaceAtMs < FACE_TOI_DA_MS else { return nil }
                // ⚠️ CAMERA TRƯỚC: khung xương đã bị lật ở trên, nhưng ML Kit chạy
                // trên ảnh THÔ nên góc mặt CHƯA lật. Lật ngang thì góc quay đổi dấu.
                return mode.camTruoc
                    ? FaceInfo(yawDeg: info.yawDeg.map { -$0 }, eyesOpen: info.eyesOpen)
                    : info
            }
            var doAnh = Measurer.measure(
                frame,
                framing: profile.framing,
                minVisibility: minVisibility,
                face: freshFace,
                vFovDeg: vFov
            )
            gocAnhLive = doAnh.tiltDeg
            // ⚠️ GÓC MÁY PHÍA CAMERA LẤY TỪ CẢM BIẾN — độ thật, cùng thang với NHÃN
            // góc của ảnh mẫu. KHÔNG suy từ khung xương: con số đó lẫn dáng đứng và
            // loại ống kính.
            let camBien = devicePitchDeg.map { mode.camTruoc ? -$0 : $0 }
            if let goc = camBien {
                doAnh.tiltDeg = goc
                doAnh.pitchCue[.GOC_MAY] = goc
                doAnh.elevationDeg = Measurer.gocNhin(goc, anchorY: doAnh.elevationAnchorY, vFovDeg: vFov)
                live = doAnh
            } else {
                // Cảm biến chưa cho số (chưa có dữ liệu): bỏ ghiến góc máy khỏi phép đo.
                live = doAnh.boGocMayTuAnh()
            }
        } else {
            live = nil
        }

        // ⚠️ TẠM — xem `CaptureUiState.debugGocMay`.
        let dbgGoc: String = {
            func f(_ v: Double?) -> String { v.map { String(format: "%+.0f°", $0) } ?? "--" }
            let camBien = devicePitchDeg.map { mode.camTruoc ? -$0 : $0 }
            return "GÓC MÁY   cảm biến " + f(camBien) + "   ·   suy từ ảnh " + f(gocAnhLive)
        }()

        // ⚠️ TẠM — xem `CaptureUiState.debugDo`.
        let dbg: String? = {
            guard let t = profile?.measurement, let l = live else { return nil }
            func f(_ v: Double?) -> String { v.map { String(format: "%+.0f", $0) } ?? "--" }
            func g(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "--" }
            // m4: số sau là CẢM BIẾN. cỡ: có chữ "m" là đang so bằng khung mặt.
            let coM = t.scale == nil && t.faceScale != nil
            return "m3 " + f(t.elevationDeg) + "/" + f(l.elevationDeg) +
                "  m4 " + f(t.tiltDeg) + "/" + f(l.tiltDeg) +
                "  cỡ" + (coM ? "m " : " ") +
                (coM ? g(t.faceScale) + "/" + g(l.faceScale) : g(t.scale) + "/" + g(l.scale)) +
                "  vFOV " + (vFovDeg.map { String(format: "%.0f", $0) } ?? "65?")
        }()

        let result = eng?.update(
            live: live,
            nowMs: Self.wallMs(),
            angularSpeedDegPerSec: angularSpeedDegPerSec,
            prepWarning: prep,
            zoomRatio: zoomRatio,
            deviceRollDeg: deviceRollDeg,
            devicePitchDeg: devicePitchDeg,
            mode: mode,
            templateFrame: templateFrameForPose,
            liveFrame: detected ? frame : nil,
            minVis: minVisibility,
            allowSkip: state.autoMode,
            vFovDeg: vFovDeg,
            zoomMin: zoomMin
        )

        state.pose = frame
        state.personDetected = detected
        state.visiblePoints = frame.visibility.filter { $0 >= minVisibility }.count
        state.bodyYawDeg = detected ? frame.bodyYawDeg(minVisibility: minVisibility) : nil
        // Chỉ hiện để theo dõi. KHÔNG dùng con số này làm mốc đo — mốc đo luôn là
        // lớp khung hình của ảnh mẫu.
        state.liveFraming = detected ? FramingClass.detect(frame, minVisibility: minVisibility) : nil
        state.inferenceMs = stats.inferenceTimeMs
        state.frameWidth = rongCat
        state.frameHeight = caoCat
        state.criteria = result?.statuses ?? []
        state.cue = result?.cue
        state.cueForModel = result?.cueForModel == true
        state.prepWarning = prep
        state.readyToCapture = result?.readyToCapture ?? false
        state.matchPercent = result?.matchPercent
        state.readyToPose = result?.readyToPose == true
        state.stableForMs = result?.stableForMs ?? 0
        state.debugDo = dbg
        state.debugGocMay = dbgGoc
    }

    // -----------------------------------------------------------------
    // Quay
    // -----------------------------------------------------------------

    /// Người dùng đổi giữa quay video và chụp liên tục.
    func onModeChanged(burst: Bool) {
        state.burstMode = burst
        state.burstTaken = 0
    }

    func onBurstProgress(_ taken: Int) {
        state.burstTaken = taken
    }

    func onRecordingStarted() {
        state.recording = true
        state.recordedMs = 0
    }

    func onRecordingTick(_ elapsedMs: Int64) {
        state.recordedMs = elapsedMs
    }

    func onRecordingStopped() {
        state.recording = false
    }

    func onProcessing(_ progress: Float, _ note: String) {
        state.processing = true
        state.processProgress = Double(min(max(progress, 0), 1))
        state.processNote = note
    }

    func onProcessingFailed(_ message: String) {
        state.processing = false
        state.processProgress = 0
        state.cameraError = message
    }

    func onFinished(sessionDir: URL) {
        state.processing = false
        state.processProgress = 1
        state.finishedSession = sessionDir
    }

    /// Đồng hồ monotonic — tương đương `SystemClock.elapsedRealtime()` của Android.
    static func monotonicMs() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    /// Đồng hồ tường — tương đương `System.currentTimeMillis()` của Android.
    static func wallMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}