import Foundation

/// Quy trình hướng dẫn cố định. Bước sau không được chen lên trước bước đang làm.
enum GuidanceStep: Int {
    case MACHINE_LEVEL
    case DISTANCE
    case CAMERA_ANGLE
    case ZOOM
    case COMPOSITION
    case MODEL_DIRECTION
    case POSE
}

nonisolated func guidanceStepOf(_ criterion: Criterion) -> GuidanceStep {
    switch criterion {
    case .ROLL: return .MACHINE_LEVEL
    case .PERSPECTIVE: return .DISTANCE
    case .ELEVATION, .PITCH: return .CAMERA_ANGLE
    case .SCALE: return .ZOOM
    case .CENTER: return .COMPOSITION
    case .YAW: return .MODEL_DIRECTION
    case .POSE: return .POSE
    default: return .COMPOSITION
    }
}

nonisolated extension Criterion {
    /// Vị trí khai báo trong enum — đúng thứ tự kiểm và thứ tự nhắc.
    var ordinal: Int {
        Criterion.allCases.firstIndex(of: self) ?? 0
    }
}

/// Kết quả hướng dẫn của MỘT khung hình.
struct GuidanceResult {
    /// Trạng thái từng mục, đã sắp theo thứ tự ưu tiên. Đây là thứ vẽ ra danh sách tích.
    var statuses: [CriterionStatus] = []

    /// Câu nhắc đang hiện. `nil` = không nhắc gì.
    var cue: String? = nil

    /// Cảnh báo về CÁCH CẦM MÁY, không phải về chỗ đứng.
    ///
    /// Tách khỏi 6 tiêu chí vì bản chất khác hẳn: đây là những thứ làm **mọi phép
    /// đo phía sau mất nghĩa**, nên phải sửa trước khi nói tới chuyện đứng đâu.
    var prepWarning: String? = nil

    /// Đủ điều kiện để bấm quay chưa.
    var readyToCapture: Bool = false

    /// Đã giữ ổn định được bao lâu, mili giây. Dùng để vẽ vòng đếm ngược.
    var stableForMs: Int64 = 0

    /// Câu đang hiện là câu để **ĐỌC TO CHO MẪU NGHE**. Giao diện dùng cờ này để đổi biểu tượng.
    var cueForModel: Bool = false

    /// ĐỘ GIỐNG ẢNH MẪU NGAY LÚC NÀY, 0..100. `nil` = chưa đo được gì.
    ///
    /// ⚠️ Dùng **đúng hàm chấm điểm** mà bước chọn ảnh sau khi quay dùng
    /// (`ShotScorer.score`), không phải một phép tính riêng. Đây là bất biến số 1
    /// của dự án.
    var matchPercent: Int? = nil

    /// Đã đủ giống để bắt đầu chuẩn bị tạo dáng chưa.
    var readyToPose: Bool = false

    var allPassed: Bool {
        !statuses.isEmpty && statuses.allSatisfy(resolvedForCapture)
    }
}

/// Dáng là mục hướng dẫn cuối, không được chặn việc chụp.
nonisolated func resolvedForCapture(_ status: CriterionStatus) -> Bool {
    status.criterion == .POSE ||
        (!status.pending && (status.state == .PASSING || status.skipped))
}

/// ENGINE HƯỚNG DẪN — Bước 4.
///
/// Nối ba mảnh đã có: tầng đo đạc → [CriterionGate] (khoá/mở) → [CuePresenter]
/// (chọn câu). Bản thân nó **không đo gì cả**.
///
/// ⚠️ BẤT BIẾN SỐ 1 CỦA DỰ ÁN được giữ ở đây: độ lệch lấy từ `ShotScorer.deviation`
/// — **đúng hàm mà bước chấm điểm dùng**.
nonisolated final class GuidanceEngine {

    private let profile: TemplateProfile

    /// Chỉ những mục ảnh mẫu này áp dụng, và chỉ những mục hướng dẫn được realtime.
    private let applicable: [Criterion]

    private let steps: [[Criterion]]

    private var currentStepIndex = 0
    private var currentStepSinceMs: Int64?
    private var skipped = Set<Criterion>()

    private var gates: [Criterion: CriterionGate] = [:]

    private let presenter = CuePresenter()

    /// Đếm số khung liên tiếp đo được. Chưa đủ thì chưa tin số đo.
    private var validFrames = 0

    /// Mốc bắt đầu đạt đủ mọi điều kiện. `nil` = đang chưa đạt.
    private var allGoodSinceMs: Int64?

    /// Mốc bắt đầu hiện một câu dành cho MẪU. `nil` = đang không nói với mẫu.
    ///
    /// Trong khoảng [Self.MODEL_CUE_FREEZE_MS] kể từ mốc này, các mục về MÁY bị **đóng
    /// băng** — không sinh câu nhắc.
    private var modelCueSinceMs: Int64?

    /// Lần đầu máy đứng yên. `nil` = chưa yên lần nào kể từ khi mở màn chụp.
    private var daYenLanDauMs: Int64?

    init(profile: TemplateProfile) {
        self.profile = profile
        let active = profile.activeFor(Stage.GUIDANCE)
        let sorted = active.sorted {
            let a = guidanceStepOf($0).rawValue
            let b = guidanceStepOf($1).rawValue
            if a != b { return a < b }
            return $0.ordinal < $1.ordinal
        }
        self.applicable = sorted

        var grouped: [Int: [Criterion]] = [:]
        for c in sorted {
            grouped[guidanceStepOf(c).rawValue, default: []].append(c)
        }
        self.steps = grouped.keys.sorted().compactMap { grouped[$0] }

        var built: [Criterion: CriterionGate] = [:]
        for c in sorted { built[c] = CriterionGate(c) }
        self.gates = built
    }

    /// Nạp một khung hình.
    ///
    /// - Parameter live số đo khung hình camera, đã đi qua **cùng hàm đo** với ảnh mẫu
    /// - Parameter nowMs mốc thời gian của khung hình
    /// - Parameter angularSpeedDegPerSec tốc độ quay của máy, từ con quay hồi chuyển
    /// - Parameter prepWarning cảnh báo cầm máy (xoay ngang, đang zoom). `nil` = ổn.
    func update(live: PoseMeasurement?,
                nowMs: Int64,
                angularSpeedDegPerSec: Double,
                prepWarning: String? = nil,
                zoomRatio: Float = 1.0,
                deviceRollDeg: Double? = nil,
                devicePitchDeg: Double? = nil,
                mode: ShootMode = .NGUOI_KHAC,
                templateFrame: PoseFrame? = nil,
                liveFrame: PoseFrame? = nil,
                minVis: Float = 0.5,
                allowSkip: Bool = false,
                vFovDeg: Double? = nil,
                zoomMin: Float = 0.5) -> GuidanceResult {
        // Chưa thấy người: xoá đồng hồ ổn định, nhưng KHÔNG reset các cổng —
        // mất dấu một lúc rồi bắt lại được thì không nên bắt người ta làm lại từ đầu.
        if live == nil {
            validFrames = 0
            allGoodSinceMs = nil
            currentStepSinceMs = nil
            let statuses = applicable.map { c in
                let st = gates[c]!.state
                return CriterionStatus(criterion: c,
                                       state: st == .PASSING ? .PASSING : .UNMEASURED,
                                       deviation: nil,
                                       signedDelta: nil,
                                       band: bandOf(c))
            }
            return GuidanceResult(statuses: statuses, cue: nil, prepWarning: prepWarning)
        }

        let liveM = live!

        if validFrames < GuidanceTiming.MIN_VALID_FRAMES { validFrames += 1 }

        let dev = ShotScorer.deviation(profile.measurement, liveM)

        // Điểm giống mẫu NGAY LÚC NÀY — cùng hàm với bước chấm ảnh sau khi quay.
        let total = ShotScorer.score(profile, candidate: liveM, stage: Stage.GUIDANCE,
                                     acceptOf: { c in self.bandOf(c, dev.pitchSource)?.accept }).total
        let match = total.isFinite ? Int(max(0, min(100, total.rounded()))) : nil

        let t = profile.measurement

        // Cảm biến còn tin được không, rồi mới hỏi nó lỗi nằm ở đâu.
        let tiltTrusted = devicePitchDeg.map { abs($0) < Self.DEVICE_ROLL_TRUST_PITCH_DEG } ?? false
        let rollFromDevice: Bool
        if tiltTrusted, let dr = deviceRollDeg {
            rollFromDevice = abs(dr) >= Self.DEVICE_ROLL_BLAME_DEG
        } else {
            rollFromDevice = true
        }

        // ⚠️ KIỂU CHỤP TỪ TRÊN CAO — chỉ ảnh người khác chụp có nhãn này.
        let kieuTren = mode == .NGUOI_KHAC ? profile.kieuChupTren : nil
        let zoomToiDa = kieuTren?.zoomToiDa
        let zoomSai: Bool
        if let zMax = zoomToiDa {
            zoomSai = zoomRatio > zMax + Self.ZOOM_LECH_TOI_DA
        } else {
            zoomSai = false
        }
        let duXa: Bool
        if kieuTren == .xaZoom {
            let dangCach = DistanceEstimator.estimate(scaleInFrame: liveM.scale,
                                                      realHeightMeters: liveM.anchorHeightMeters,
                                                      zoomRatio: zoomRatio,
                                                      heSo: DistanceEstimator.heSoOngKinh(vFovDeg: vFovDeg, zoomRatio: zoomRatio)) ?? 0.0
            duXa = dangCach >= DistanceEstimator.minStandoffMeters(profile.framing)
        } else {
            duXa = false
        }

        var statuses: [CriterionStatus] = applicable.map { c in
            // ⚠️ Mục ngửa/chúc phải lấy ngưỡng THEO ĐÚNG đường đo đã dùng cho khung này.
            let band = bandOf(c, c == .PITCH ? dev.pitchSource : nil)
            let deviation: Double?
            switch c {
            case .YAW:
                deviation = dev.yawDeg
            case .SCALE:
                // Sai mức zoom bắt buộc thì cỡ người có khớp cũng là ảnh khác hẳn.
                if zoomSai, let b = band { deviation = b.unlock + b.accept } else { deviation = dev.scaleRatio }
            case .CENTER:
                deviation = dev.centerX
            case .ELEVATION:
                deviation = dev.elevationDeg
            case .ROLL:
                deviation = dev.rollDeg
            case .PITCH:
                deviation = dev.pitchCue
            case .PERSPECTIVE:
                // ⚠️ ĐÃ LÙI ĐỦ XA THÌ THÔI BẮT LÙI (14/09/2026).
                deviation = dev.perspective.map { d in
                    let muonLui = (signedDelta(c, t, liveM) ?? 0.0) > 0.0
                    let dangCach = DistanceEstimator.estimate(scaleInFrame: liveM.scale,
                                                              realHeightMeters: liveM.anchorHeightMeters,
                                                              zoomRatio: zoomRatio,
                                                              heSo: DistanceEstimator.heSoOngKinh(vFovDeg: vFovDeg, zoomRatio: zoomRatio))
                    if muonLui, let dangCach,
                       dangCach >= DistanceEstimator.minStandoffMeters(profile.framing) {
                        return 0.0
                    }
                    return d
                }
            case .POSE:
                deviation = dev.poseDeg
            default:
                deviation = nil
            }

            // Chưa đủ khung liên tiếp thì coi như chưa đo được.
            let trusted = validFrames >= GuidanceTiming.MIN_VALID_FRAMES ? deviation : nil
            let state: GateState
            if let band {
                state = gates[c]!.update(deviation: trusted, band: band, nowMs: nowMs)
            } else {
                state = .UNMEASURED
            }

            let zoomYeuCau: Float? = zoomToiDa.map { min(max(zoomMin, $0), $0) }

            return CriterionStatus(
                criterion: c,
                state: state,
                deviation: trusted,
                signedDelta: signedDelta(c, t, liveM),
                band: band,
                moveMeters: moveMetersFor(c, t: t, live: liveM, zoomRatio: zoomRatio,
                                          vFovDeg: vFovDeg, zoomYeuCau: zoomYeuCau),
                walkInsteadOfZoom: c == .SCALE && !applicable.contains(.PERSPECTIVE),
                poseHint: (c == .POSE && templateFrame != nil && liveFrame != nil)
                    ? PoseDescriber.correction(template: templateFrame!, live: liveFrame!, minVis: minVis)
                    : nil,
                rollFromDevice: rollFromDevice,
                gocMauKhongCoCaoThap: (c == .PITCH && !applicable.contains(.ELEVATION)) ? t.tiltDeg : nil,
                unmeasuredTooLong: state == .UNMEASURED && gates[c]!.unmeasuredTooLong(nowMs),
                tuChup: mode.tuChup,
                latGuong: mode.latGuong,
                mayNguocChieu: mode.mayNguocChieu,
                tamTay: mode.tamTay,
                targetZoom: c == .SCALE ? targetZoomFor(t, live: liveM, currentZoom: zoomRatio) : nil,
                zoomToiDa: c == .SCALE ? zoomToiDa : nil,
                zoomSai: c == .SCALE && zoomSai,
                coGocRong: c == .SCALE && zoomMin <= Self.ZOOM_GOC_RONG_TOI_DA,
                chupTuXa: c == .SCALE && kieuTren == .xaZoom,
                duXa: duXa
            )
        }

        // Khoá bước đã đạt để tránh rung tay kéo người dùng quay lại.
        let takenSteps = Array(steps.prefix(currentStepIndex))
        let brokenStep = takenSteps.firstIndex { step in
            step.contains { criterion in
                guard let status = statuses.first(where: { $0.criterion == criterion }) else { return false }
                return !skipped.contains(criterion) &&
                    status.state == .FAILING &&
                    status.deviation != nil && status.band != nil &&
                    status.deviation! > status.band!.unlock
            }
        }
        if let broken = brokenStep {
            currentStepIndex = broken
            currentStepSinceMs = nil
            allGoodSinceMs = nil
            presenter.reset()
        }

        // Chỉ một bước được hoạt động. Các bước sau hiện trạng thái "đang chờ".
        while currentStepIndex < steps.count {
            let current = steps[currentStepIndex]
            let done = current.allSatisfy { c in
                if skipped.contains(c) { return true }
                return statuses.first { $0.criterion == c }?.state == .PASSING
            }
            if !done { break }
            currentStepIndex += 1
            currentStepSinceMs = nil
            presenter.reset()
        }

        if currentStepIndex < steps.count {
            let current = steps[currentStepIndex]
            // Cảnh báo chuẩn bị đang che câu hướng dẫn, nên khoảng thời gian đó
            // không được tính là người dùng đã thử mà vẫn bị kẹt.
            if !allowSkip || prepWarning != nil {
                currentStepSinceMs = nil
            } else {
                if currentStepSinceMs == nil { currentStepSinceMs = nowMs }
                if nowMs - currentStepSinceMs! >= Self.AUTO_SKIP_AFTER_MS {
                    for c in current
                    where statuses.first(where: { $0.criterion == c })?.state != .PASSING {
                        skipped.insert(c)
                    }
                    currentStepIndex += 1
                    currentStepSinceMs = nil
                    presenter.reset()
                }
            }
        }

        let activeCriteria = currentStepIndex < steps.count ? Set(steps[currentStepIndex]) : Set<Criterion>()
        let completedCriteria = Set(steps.prefix(currentStepIndex).flatMap { $0 })
        statuses = statuses.map { status in
            if skipped.contains(status.criterion) {
                var s = status; s.skipped = true; return s
            }
            if completedCriteria.contains(status.criterion) {
                var s = status; s.state = .PASSING; return s
            }
            if activeCriteria.contains(status.criterion) { return status }
            var s = status; s.pending = true; return s
        }

        // --- Chọn các mục đáng nhắc ---
        var failing = statuses
            .filter { !$0.pending && !$0.skipped }
            .filter { s -> Bool in
                switch s.state {
                case .FAILING:
                    // Sàn hành động: lệch ít tới mức không ai sửa nổi thì im.
                    guard let d = s.deviation, let b = s.band else { return false }
                    return d - b.accept >= b.actionFloor
                case .UNMEASURED:
                    // ⚠️ MỤC KHÔNG ĐO ĐƯỢC QUÁ LÂU CŨNG PHẢI ĐƯỢC NÓI (12/09/2026).
                    return s.unmeasuredTooLong
                default:
                    return false
                }
            }
            .sorted { $0.criterion.ordinal < $1.criterion.ordinal }
        failing = gopCaoVaChuc(failing)

        // Chỉ khi toàn bộ bước về máy đã hoàn tất hoặc được bỏ qua thì mới chuyển
        // sang hướng mẫu. GREY/UNMEASURED không phải là đã xong.
        let cameraClean = statuses
            .filter { !$0.criterion.forModel }
            .allSatisfy { !$0.pending && ($0.state == .PASSING || $0.skipped) }

        // Mục ÁP DỤNG mà khung hình không đo được, kéo dài đủ lâu. Ưu tiên THẤP NHẤT.
        let stuckUnmeasured = statuses.filter {
            !$0.pending && !$0.skipped && $0.unmeasuredTooLong
        }

        var cueCandidates: [CriterionStatus]
        if cameraClean {
            cueCandidates = failing
        } else {
            cueCandidates = failing.filter { !$0.criterion.forModel }
        }
        if cueCandidates.isEmpty { cueCandidates = stuckUnmeasured }

        // Đang nói với mẫu: đóng băng các mục về máy vài giây.
        // ⚠️ Tự chụp thì KHÔNG đóng băng — không có ai để nói.
        let talking = !mode.tuChup &&
            modelCueSinceMs.map { nowMs - $0 < Self.MODEL_CUE_FREEZE_MS } == true
        if talking {
            let modelOnly = cueCandidates.filter { $0.criterion.forModel }
            if !modelOnly.isEmpty { cueCandidates = modelOnly }
        }

        // ⚠️ ĐỦ GIỐNG RỒI THÌ NGỪNG BẮT BẺ.
        let readyToPose = cameraClean

        let poseCandidates = cueCandidates.filter { $0.criterion.forModel }

        // ⚠️ IM LẶNG TRONG LÚC NGƯỜI DÙNG ĐANG TỰ ĐẶT MÁY — chờ máy đứng yên đủ
        // lâu MỘT LẦN rồi mới bắt đầu nói.
        if daYenLanDauMs == nil &&
            angularSpeedDegPerSec <= GuidanceTiming.MAX_ANGULAR_SPEED_DEG_PER_SEC {
            daYenLanDauMs = nowMs
        }
        let daQuaLucDatMay = daYenLanDauMs.map { nowMs - $0 >= Self.CHO_DAT_MAY_MS } == true

        let cue: String?
        if prepWarning != nil {
            cue = nil
        } else if !daQuaLucDatMay {
            cue = nil
        } else if readyToPose {
            cue = presenter.update(failing: poseCandidates, nowMs: nowMs,
                                   angularSpeedDegPerSec: angularSpeedDegPerSec)
        } else {
            cue = presenter.update(failing: cueCandidates, nowMs: nowMs,
                                   angularSpeedDegPerSec: angularSpeedDegPerSec)
        }

        // ⚠️ Không hỏi `criterion.forModel` — mục NGHIÊNG NGANG đổi vai theo từng
        // khung hình: cảm biến báo máy thẳng thì câu của nó là câu cho MẪU.
        let cueForModel = cue != nil && cueCandidates.first?.isModelCue == true
        if cueForModel && modelCueSinceMs == nil {
            modelCueSinceMs = nowMs
        } else if !cueForModel && !talking {
            modelCueSinceMs = nil
        }

        // --- Cổng chụp ---
        let steady = angularSpeedDegPerSec <= GuidanceTiming.MAX_ANGULAR_SPEED_DEG_PER_SEC

        let allResolved = !statuses.isEmpty && statuses.allSatisfy(resolvedForCapture)
        let good = prepWarning == nil && allResolved && steady

        if good {
            if allGoodSinceMs == nil { allGoodSinceMs = nowMs }
        } else {
            allGoodSinceMs = nil
        }
        let stableFor = allGoodSinceMs.map { nowMs - $0 } ?? 0

        return GuidanceResult(
            statuses: statuses,
            cue: cue,
            prepWarning: prepWarning,
            readyToCapture: good && stableFor >= GuidanceTiming.DWELL_MS,
            stableForMs: stableFor,
            cueForModel: cueForModel,
            matchPercent: match,
            readyToPose: readyToPose
        )
    }

    // MARK: - Helpers

    /// Zoom đích ở nguyên vị trí hiện tại: kích thước trong khung tỉ lệ thuận với zoom.
    private func targetZoomFor(_ template: PoseMeasurement,
                               live: PoseMeasurement,
                               currentZoom: Float) -> Float? {
        guard let (target, current) = ShotScorer.scalePair(template, live) else { return nil }
        if current <= 1e-6 { return nil }
        return max(0.1, currentZoom * Float(target / current))
    }

    /// GỘP "máy cao/thấp" với "máy ngửa/chúc" thành MỘT câu khi chúng cùng chiều.
    ///
    /// Chỉ gộp khi CÙNG CHIỀU (cần nâng VÀ cần chúc, hoặc cần hạ VÀ cần hất).
    private func gopCaoVaChuc(_ ds: [CriterionStatus]) -> [CriterionStatus] {
        guard let cao = ds.first(where: { $0.criterion == .ELEVATION && $0.state == .FAILING }) else { return ds }
        guard let chuc = ds.first(where: { $0.criterion == .PITCH && $0.state == .FAILING }) else { return ds }
        guard let a = cao.signedDelta, let b = chuc.signedDelta else { return ds }
        if a * b <= 0.0 { return ds }
        return ds.compactMap {
            if $0.criterion == .PITCH { return nil }
            if $0.criterion == .ELEVATION {
                var s = $0; s.kemChuc = true; return s
            }
            return $0
        }
    }

    /// QUÃNG ĐƯỜNG CẦN ĐI, mét — chỉ cho hai mục liên quan tới chỗ đứng.
    ///
    ///     đích = MAX( mốc tối thiểu của lớp ảnh , khoảng cách để khớp khung ở 1x )
    private func moveMetersFor(_ c: Criterion,
                               t: PoseMeasurement,
                               live: PoseMeasurement,
                               zoomRatio: Float,
                               vFovDeg: Double?,
                               zoomYeuCau: Float?) -> Double? {
        if c != .PERSPECTIVE && c != .SCALE { return nil }
        let heSo = DistanceEstimator.heSoOngKinh(vFovDeg: vFovDeg, zoomRatio: zoomRatio)
        guard let now = DistanceEstimator.estimate(scaleInFrame: live.scale,
                                                   realHeightMeters: live.anchorHeightMeters,
                                                   zoomRatio: zoomRatio, heSo: heSo)
        else { return nil }
        let atOneX = DistanceEstimator.estimate(scaleInFrame: t.scale,
                                                realHeightMeters: live.anchorHeightMeters,
                                                zoomRatio: 1.0, heSo: heSo)
        let target: Double
        if let zoomYeuCau {
            // Zoom cố định (đứng gần 1x, góc rộng 0.5x): đứng sát là đúng ý ảnh.
            guard let d = DistanceEstimator.estimate(scaleInFrame: t.scale,
                                                     realHeightMeters: live.anchorHeightMeters,
                                                     zoomRatio: zoomYeuCau, heSo: heSo)
            else { return nil }
            target = d
        } else {
            target = max(DistanceEstimator.minStandoffMeters(profile.framing), atOneX ?? 0.0)
        }
        return abs(target - now)
    }

    private func bandOf(_ c: Criterion, _ pitchSource: PitchSource? = nil) -> Band? {
        GuidanceConfig.bandFor(criterion: c, framing: profile.framing,
                               templateScale: profile.measurement.scale,
                               pitchSource: pitchSource)
    }

    /// Hiệu CÓ DẤU giữa khung hình và ảnh mẫu — chỉ để chọn chữ, không dùng để chấm.
    ///
    /// Đây là phép TRỪ trên hai số đã đo xong, không phải một phép đo thứ hai — nên
    /// không phá bất biến "cùng một hàm".
    private func signedDelta(_ c: Criterion, _ t: PoseMeasurement, _ live: PoseMeasurement) -> Double? {
        switch c {
        case .YAW:
            // ⚠️ Cùng luật "chỉ so khi cùng đường đo": thiếu đường ưu tiên thì BỎ.
            let a: Double?
            let b: Double?
            switch t.framing.yawSource {
            case .faceYaw: a = t.faceYawDeg; b = live.faceYawDeg
            case .body3D: a = t.yawDeg; b = live.yawDeg
            }
            guard let a, let b else { return nil }
            var d = b - a
            while d > 180.0 { d -= 360.0 }
            while d <= -180.0 { d += 360.0 }
            return d

        case .SCALE:
            guard let (a, b) = ShotScorer.scalePair(t, live), a > 1e-6 else { return nil }
            return (b - a) / a

        case .ROLL:
            for src in [RollSource.SPINE, RollSource.SHOULDERS] {
                guard let a = t.rollDeg[src], let b = live.rollDeg[src] else { continue }
                return b - a
            }
            return nil

        case .CENTER:
            return diff(t.centerX, live.centerX)

        case .ELEVATION:
            return diff(t.elevationDeg, live.elevationDeg)

        case .PITCH:
            for src in [PitchSource.GOC_MAY, PitchSource.LEGS] {
                guard let a = t.pitchCue[src], let b = live.pitchCue[src] else { continue }
                return b - a
            }
            return nil

        case .PERSPECTIVE:
            // Chọn đúng cặp đoạn mà cả hai bên cùng có — nếu không thì dấu của hiệu vô nghĩa.
            for src in [PerspectiveSource.TORSO_ANKLE, PerspectiveSource.TORSO_KNEE] {
                guard let a = t.perspectiveIndex[src], let b = live.perspectiveIndex[src] else { continue }
                return b - a
            }
            return nil

        default:
            return nil
        }
    }

    private func diff(_ t: Double?, _ c: Double?) -> Double? {
        guard let t, let c else { return nil }
        return c - t
    }

    /// Về trạng thái ban đầu. Gọi khi vào lại màn hình hoặc đổi ảnh mẫu.
    func reset() {
        gates.values.forEach { $0.reset() }
        presenter.reset()
        validFrames = 0
        allGoodSinceMs = nil
        modelCueSinceMs = nil
        daYenLanDauMs = nil
        currentStepIndex = 0
        currentStepSinceMs = nil
        skipped.removeAll()
    }

    // MARK: - Hằng số

    /// Zoom vượt mức tối đa quá chừng này thì coi là sai zoom.
    static let ZOOM_LECH_TOI_DA: Float = 0.08

    /// Máy zoom ra được tới mức này là có ống góc rộng — mới gợi ý kiểu mắt cá.
    static let ZOOM_GOC_RONG_TOI_DA: Float = 0.7

    /// Giữ im các mục về máy ngần này sau khi bắt đầu nói với mẫu.
    static let MODEL_CUE_FREEZE_MS: Int64 = 4_000

    /// Khoảng ba chu kỳ câu nhắc; sau đó chế độ tự động được phép đi tiếp.
    static let AUTO_SKIP_AFTER_MS = GuidanceTiming.CUE_MIN_DISPLAY_MS * 3

    /// Mốc điểm dùng cho hiển thị mức giống và các bài kiểm thử chấm điểm.
    static let READY_PERCENT = 85

    /// Máy phải đứng yên bấy nhiêu mili-giây rồi app mới bắt đầu nói.
    static let CHO_DAT_MAY_MS: Int64 = 1_000

    static let DEVICE_ROLL_BLAME_DEG = 3.0

    /// Máy chúc/ngửa quá mức này thì NGỪNG tin cảm biến vẹo.
    static let DEVICE_ROLL_TRUST_PITCH_DEG = 60.0
}
