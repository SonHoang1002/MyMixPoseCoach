import Foundation

/// CHẤM ĐIỂM MỘT KHUNG HÌNH so với ảnh mẫu.
///
/// ⚠️ PHÂN BIỆT RÕ hai chỗ dùng chung tầng đo:
///
///  - **Hướng dẫn realtime** ([Stage.GUIDANCE]) — trả lời *"đã đạt CHƯA"*. Câu đó
///    **bắt buộc** có ngưỡng đo trên máy thật, `accept` ≥ 3× độ lệch chuẩn. Chưa làm.
///  - **Xếp hạng chọn ảnh** ([Stage.SELECTION]) — chỉ so các khung VỚI NHAU, thêm
///    các tiêu chí hậu kỳ. **Không cần ngưỡng nào**, nên chạy được ngay.
///
/// Cả hai đọc từ **cùng một [TemplateProfile]**, nên không thể xảy ra chuyện hướng
/// dẫn chấm một kiểu còn chọn ảnh chấm một kiểu khác — lỗi mà bản iOS mắc phải.

/// Độ lệch từng mục giữa một khung hình và ảnh mẫu. `nil` = KHÔNG ĐO ĐƯỢC ở khung này.
nonisolated struct ShotDeviation {
    /// Chênh hướng mẫu, ĐỘ (đã xử lý vòng qua ±180°).
    var yawDeg: Double?

    /// ĐƯỜNG ĐO đã dùng cho [yawDeg]. `nil` khi không đo được.
    ///
    /// Phải đọc kèm [yawDeg]: góc mặt và góc thân có gốc 0 khác nhau, trộn hai
    /// đường là đo nhầm đại lượng mà số vẫn trông hợp lệ.
    var yawSource: YawSource?

    /// Chênh xa/gần, dạng TỈ LỆ TƯƠNG ĐỐI so với mẫu (0,2 = lệch 20%).
    var scaleRatio: Double?

    /// Chênh trái/phải, theo tỉ lệ bề ngang khung hình.
    var centerX: Double?

    /// Chênh cao/thấp, theo tỉ lệ chiều cao khung hình.
    var elevationDeg: Double?

    /// Chênh NGHIÊNG NGANG, ĐỘ. Luôn dương.
    var rollDeg: Double?

    /// Đường đo đã dùng cho [rollDeg]. `nil` khi không đo được.
    var rollSource: RollSource?

    /// Chênh độ méo phối cảnh (mục ngửa/chúc). Không đơn vị.
    var pitchCue: Double?

    /// ĐƯỜNG ĐO đã dùng cho [pitchCue]. `nil` khi không đo được.
    ///
    /// ⚠️ Phải đọc kèm [pitchCue] vì **mỗi đường đo có ngưỡng riêng**: đo bằng chân
    /// nhiễu 0,016, đo bằng mặt nhiễu 0,104 — gấp 6,5 lần. Dùng chung một ngưỡng
    /// cho cả hai thì đường đo bằng mặt sẽ nhấp nháy liên tục.
    var pitchSource: PitchSource?

    /// Chênh ĐỘ MẠNH PHỐI CẢNH. Không đơn vị, **miễn nhiễm với zoom**.
    ///
    /// Lệch dương = khung hình đang đứng GẦN hơn ảnh mẫu; âm = đang đứng XA hơn.
    /// Đọc cùng [scaleRatio] thì tách được "đi lại gần" khỏi "zoom vào" — xem
    /// ⚠️ CHỈ GHI NHẬT KÝ, không chấm điểm — xem FOOTGUNS mục 37.
    var perspective: Double?

    /// Chênh dáng, ĐỘ, trung bình các khớp so được.
    var poseDeg: Double?
}

/// Chất lượng HẬU KỲ của một khung hình — chỉ dùng ở bước chọn ảnh.
///
/// Cả hai đều là điểm 0..1 (càng cao càng tốt), không phải độ lệch: chúng chấm
/// **chính tấm ảnh chụp ra**, không so với ảnh mẫu.
nonisolated struct PostQuality {
    /// Độ nét đã chuẩn hoá trong nội bộ lần quay.
    var sharpness: Double?

    /// Mép khung có cắt ngang khớp không. 1 = không cắt vào khớp nào.
    var crop: Double?

    /// Mắt có mở không, 0..1. `nil` = không đo được, sẽ bị bỏ ra chứ không trừ điểm.
    var eyesOpen: Double? = nil
}

/// Điểm của một khung hình, kèm phần tách nhỏ để soi khi số liệu trông sai.
nonisolated struct ShotScore {
    /// Điểm tổng, 0..100. Càng cao càng giống ảnh mẫu.
    var total: Double

    var deviation: ShotDeviation

    /// Điểm từng mục, 0..1. Chỉ chứa mục THỰC SỰ được chấm.
    var perCriterion: [String: Double]

    /// Tổng trọng số thực dùng — thấp nghĩa là nhiều mục bị bỏ ra.
    var weightUsed: Double

    /// HỆ SỐ HƯỚNG MẪU, 0..1. Nhân thẳng vào điểm tổng.
    ///
    /// 1 = mẫu quay đúng hướng ảnh mẫu, [DIRECTION_FLOOR] = quay sai hẳn.
    var directionFactor: Double = 1.0

    /// Có đủ căn cứ để tin điểm này không.
    ///
    /// Khung chỉ chấm được 1-2 mục vẫn có thể ra điểm cao, nhưng đó là điểm cao
    /// của sự thiếu thông tin. Dùng cờ này để không đẩy nó lên đầu bảng.
    var trustworthy: Bool { perCriterion.count >= 3 }
}

nonisolated enum ShotScorer {

    /// Lệch đúng bằng ngưỡng đạt thì coi như mất bấy nhiêu phần trọng số.
    ///
    /// 0,10 nghĩa là **mọi mục vừa chạm ngưỡng đạt ⇒ điểm tổng 90**. Chọn 0,10 chứ
    /// không phải 0 để trong vùng đạt vẫn còn phân biệt được khung nào đẹp hơn —
    /// bộ giữ khung cần XẾP HẠNG, cào bằng thì nó giữ lại 5 khung ngẫu nhiên.
    static let VUNG_DAT = 0.10

    /// So một khung hình với ảnh mẫu.
    ///
    /// @param profile hồ sơ ảnh mẫu — quyết định **những mục nào được chấm**
    /// @param candidate kết quả đo khung hình đang xét
    /// @param stage đang hướng dẫn realtime hay đang chọn ảnh
    /// @param post chất lượng hậu kỳ; bỏ qua hoàn toàn khi [stage] là GUIDANCE
    static func score(
        _ profile: TemplateProfile,
        candidate: PoseMeasurement,
        stage: Stage,
        post: PostQuality? = nil,
        /// Ngưỡng ĐẠT của từng mục, cùng đơn vị với độ lệch. `nil` = không biết.
        ///
        /// ⚠️ Có nó thì điểm số mới ĂN KHỚP với dấu tích — xem [VUNG_DAT].
        /// Không truyền thì điểm vẫn tính được, chỉ là thang cũ.
        acceptOf: ((Criterion) -> Double?)? = nil
    ) -> ShotScore {
        let dev = deviation(profile.measurement, candidate)
        let applicable = profile.activeFor(stage)

        var parts = [String: Double]()
        var weighted = 0.0
        var weightSum = 0.0

        /// Uốn lại thang điểm cho ăn khớp với dấu tích.
        ///
        /// ## Vấn đề
        ///
        /// `accept` (ngưỡng đạt) và `reference` (lệch hết cỡ) là hai thang rời
        /// nhau — ví dụ mục 3: đạt ở 6°, hết cỡ ở 35°. Nên một khung ĐẠT SÁT
        /// ngưỡng vẫn mất 6/35 = 17% trọng số của mục đó. Cộng dồn 6 mục thì
        /// **xanh hết vẫn chỉ ~73%**.
        ///
        /// Đo trên video test thật (12/09/2026): 7/7 tích xanh cho **73%**, trong
        /// khi một khung khác 4/6 tích lại cho **84%**. Điểm và tích đi ngược
        /// chiều nhau — với người dùng thì đó là app tự mâu thuẫn.
        ///
        /// ## Cách sửa
        ///
        /// Chia làm hai đoạn:
        /// - Trong ngưỡng đạt: badness chạy 0 → [VUNG_DAT]. Đạt sát ngưỡng vẫn
        ///   giữ được 90% trọng số.
        /// - Ngoài ngưỡng: chạy tiếp [VUNG_DAT] → 1 cho tới mốc `reference`.
        ///
        /// Nhờ vậy **mọi mục xanh ⇒ điểm ≥ 90**, nên mốc 85% mà PO yêu cầu mới
        /// với tới được.
        func uon(_ c: Criterion, _ lech: Double?) -> Double? {
            guard let lech = lech else { return nil }
            guard let accept = acceptOf?(c) else { return lech / c.reference }
            if accept <= 1e-9 { return lech / c.reference }
            if lech <= accept {
                return lech / accept * VUNG_DAT
            } else {
                let con = max(c.reference - accept, 1e-9)
                return VUNG_DAT + (lech - accept) / con * (1.0 - VUNG_DAT)
            }
        }

        /// @param badness 0 = trùng khớp, 1 = lệch hết cỡ. `nil` = không đo được ở khung này.
        func add(_ c: Criterion, _ badness: Double?) {
            // Mục không thuộc hồ sơ ảnh mẫu thì KHÔNG BAO GIỜ chấm — kể cả khi
            // khung hình này tình cờ đo được nó. Đây là khác biệt cốt lõi giữa
            // "template không cần mục này" và "khung này không đo được mục này".
            if !applicable.contains(c) { return }
            guard let badness = badness else { return }
            let s = 1.0 - min(max(badness, 0.0), 1.0)
            // ⚠️ Trọng số lấy theo LỚP KHUNG HÌNH của ảnh mẫu, không phải hằng số.
            // Ảnh chân dung coi trọng "xa/gần" hơn hẳn ảnh toàn thân.
            let w = c.weightFor(profile.framing)
            parts[c.key] = s
            weighted += s * w
            weightSum += w
        }

        // ⚠️ HƯỚNG MẪU KHÔNG nằm trong phép cộng trung bình — nó là HỆ SỐ NHÂN,
        // xử lý riêng bên dưới. Xem [directionFactor] để biết vì sao.
        add(.SCALE, uon(.SCALE, dev.scaleRatio))
        add(.CENTER, uon(.CENTER, dev.centerX))
        add(.ELEVATION, uon(.ELEVATION, dev.elevationDeg))
        add(.PITCH, uon(.PITCH, dev.pitchCue))
        add(.PERSPECTIVE, uon(.PERSPECTIVE, dev.perspective))
        add(.POSE, uon(.POSE, dev.poseDeg))

        // Hậu kỳ đưa vào dạng ĐIỂM chứ không phải độ lệch, nên đảo lại thành badness.
        add(.SHARPNESS, post?.sharpness.map { 1.0 - min(max($0, 0.0), 1.0) })
        add(.CROP, post?.crop.map { 1.0 - min(max($0, 0.0), 1.0) })
        add(.EYES_OPEN, post?.eyesOpen.map { 1.0 - min(max($0, 0.0), 1.0) })

        // --- HƯỚNG MẪU: hệ số nhân, không phải một mục cộng vào ---
        //
        // ⚠️ QUYẾT ĐỊNH SẢN PHẨM, không phải chi tiết kỹ thuật: **mẫu quay sai
        // hướng thì tấm ảnh đã sai rồi**, dù mọi thứ khác đều chuẩn. Ảnh mẫu quay
        // mặt mà mẫu quay lưng thì không có cách nào cứu bằng việc đứng đúng chỗ.
        //
        // Trước đây hướng mẫu chỉ là 1 trong 6 mục cộng trung bình, nên một tấm
        // SAI HƯỚNG HOÀN TOÀN vẫn được 49/100 nhờ năm mục kia — đã gặp thật trên
        // máy. Con số đó vừa sai vừa gây hiểu nhầm.
        //
        // Vì sao có [DIRECTION_FLOOR] thay vì nhân thẳng về 0: bộ giữ khung hình
        // cần XẾP HẠNG các khung với nhau. Nếu cả trăm khung đều sai hướng và cùng
        // ra 0 điểm thì không còn gì để so, app sẽ giữ lại 5 khung ngẫu nhiên.
        // Giữ một sàn nhỏ thì thứ tự vẫn còn, mà điểm vẫn đủ thấp để nói rõ
        // "tấm này chưa đạt".
        let direction = directionFactor(profile, dev, applicable)

        // Hướng mẫu VẪN phải có mặt trong bảng phân tích, dù không cộng vào trung
        // bình: màn kết quả hiển thị nó, và phép "không tấm nào đạt mục nào" cũng
        // đọc từ đây. Bỏ khỏi bảng thì cảnh báo sai hướng im lặng ngừng hoạt động.
        if applicable.contains(.YAW), let yawDeg = dev.yawDeg {
            parts[Criterion.YAW.key] =
                1.0 - min(max(yawDeg / Criterion.YAW.reference, 0.0), 1.0)
        }

        // Khi hướng mẫu là mục DUY NHẤT đo được, không có gì để lấy trung bình —
        // lúc đó chính hệ số hướng là điểm. Để 0 như trước sẽ biến "khớp hướng hoàn
        // hảo" thành 0 điểm, sai hẳn nghĩa.
        let yawMeasured = applicable.contains(.YAW) && dev.yawDeg != nil
        let base: Double
        if weightSum > 0.0 {
            base = weighted / weightSum
        } else if yawMeasured {
            base = 1.0
        } else {
            base = 0.0          // không đo được mục nào cả
        }
        let total = base * direction * 100.0

        return ShotScore(
            total: total,
            deviation: dev,
            perCriterion: parts,
            weightUsed: weightSum,
            directionFactor: direction
        )
    }

    /// Hệ số hướng mẫu, [DIRECTION_FLOOR]..1.
    ///
    /// Không đo được hướng (mẫu quay lưng hoàn toàn, không thấy vai) → trả **1**,
    /// tức không phạt. "Không đo được" khác "sai" — luật số 4 của dự án.
    private static func directionFactor(
        _ profile: TemplateProfile,
        _ dev: ShotDeviation,
        _ applicable: Set<Criterion>
    ) -> Double {
        if !applicable.contains(.YAW) { return 1.0 }
        guard let d = dev.yawDeg else { return 1.0 }
        let ok = 1.0 - min(max(d / Criterion.YAW.reference, 0.0), 1.0)
        return DIRECTION_FLOOR + (1.0 - DIRECTION_FLOOR) * ok
    }

    /// Sàn của hệ số hướng: sai hướng hết cỡ thì điểm còn 12% chứ không về 0.
    ///
    /// Đủ thấp để không ai nhầm là "tạm được", đủ khác 0 để còn xếp hạng được giữa
    /// các khung cùng sai hướng.
    static let DIRECTION_FLOOR = 0.12

    /// Độ lệch từng mục. Mục nào một trong hai bên không đo được thì trả `nil`.
    static func deviation(_ template: PoseMeasurement, _ candidate: PoseMeasurement) -> ShotDeviation {
        return ShotDeviation(
            yawDeg: yawDeviation(template, candidate)?.1,
            yawSource: yawDeviation(template, candidate)?.0,
            // Chênh xa/gần tính theo TỈ LỆ TƯƠNG ĐỐI, không theo hiệu số tuyệt đối:
            // lệch 0,05 trên ảnh chân dung (mốc ~0,15) là rất nhiều, còn lệch 0,05
            // trên ảnh toàn thân (mốc ~0,85) thì gần như không thấy.
            scaleRatio: scalePair(template, candidate).flatMap { p -> Double? in
                if p.0 <= 1e-6 { return nil }
                return abs(p.1 - p.0) / p.0
            },
            centerX: pair(template.centerX, candidate.centerX) { t, c in abs(c - t) },
            elevationDeg: pair(template.elevationDeg, candidate.elevationDeg) { t, c in abs(c - t) },
            rollDeg: rollDeviation(template, candidate)?.1,
            rollSource: rollDeviation(template, candidate)?.0,
            pitchCue: pitchDeviation(template, candidate)?.1,
            pitchSource: pitchDeviation(template, candidate)?.0,
            perspective: perspectiveDeviation(template, candidate),
            poseDeg: poseDiff(template.poseAngles, candidate.poseAngles)
        )
    }

    /// Chênh độ méo phối cảnh — **chỉ so khi hai bên dùng CÙNG một cặp mốc**.
    ///
    /// Duyệt các cặp theo thứ tự ưu tiên, lấy cặp đầu tiên mà **cả ảnh mẫu lẫn
    /// khung hình cùng đo được**. Không có cặp chung nào thì trả `nil` = không đo
    /// được, và theo luật số 4 thì mục này bị bỏ ra chứ không bị trừ điểm.
    ///
    /// ⚠️ Không bao giờ được lấy cặp tốt nhất của mỗi bên rồi trừ nhau. Ảnh mẫu đo
    /// bằng mắt–tai mà khung hình đo bằng ba đoạn thân thì hai con số thuộc hai
    /// thang khác hẳn — phép trừ ra số vô nghĩa nhưng trông vẫn hoàn toàn hợp lệ.
    /// Đây đúng cái bẫy mà `yawDeviation` phía trên cũng phải tránh.
    ///
    /// Chênh độ méo hình thang — **chỉ so khi hai bên dùng CÙNG một đường đo**.
    ///
    /// Ưu tiên [PitchSource.LEGS] vì nhiễu của nó nhỏ hơn 6,5 lần. Chỉ lùi về
    /// [PitchSource.FACE] khi một trong hai bên không có đường chân — ảnh chân dung,
    /// dáng ngồi che chân, hoặc mẫu vừa đá chân về phía ống kính.
    ///
    /// ⚠️ Trước khi có hàm này, ảnh mẫu đo bằng CHÂN bị trừ thẳng cho khung camera
    /// đo bằng MẶT. Hai con số thuộc hai thang khác hẳn nhau, phép trừ ra kết quả
    /// vô nghĩa mà trông vẫn hợp lệ — đúng loại lỗi không bao giờ lộ khi chạy thử.
    ///
    /// Chênh nghiêng ngang — **chỉ so khi hai bên cùng đường đo**. Ưu tiên trục thân.
    private static func rollDeviation(_ t: PoseMeasurement, _ c: PoseMeasurement) -> (RollSource, Double)? {
        // Thứ tự `RollSource.entries` bên Kotlin: SPINE trước, rồi SHOULDERS.
        for source in [RollSource.SPINE, RollSource.SHOULDERS] {
            guard let a = t.rollDeg[source] else { continue }
            guard let b = c.rollDeg[source] else { continue }
            return (source, abs(b - a))
        }
        return nil
    }

    private static func pitchDeviation(_ t: PoseMeasurement, _ c: PoseMeasurement) -> (PitchSource, Double)? {
        // Thứ tự `PitchSource.entries` bên Kotlin: GOC_MAY trước, rồi LEGS.
        for source in [PitchSource.GOC_MAY, PitchSource.LEGS] {
            guard let a = t.pitchCue[source] else { continue }
            guard let b = c.pitchCue[source] else { continue }
            return (source, abs(b - a))
        }
        return nil
    }

    private static func perspectiveDeviation(_ t: PoseMeasurement, _ c: PoseMeasurement) -> Double? {
        // Thứ tự `PerspectiveSource.entries` bên Kotlin: TORSO_ANKLE rồi TORSO_KNEE.
        for source in [PerspectiveSource.TORSO_ANKLE, PerspectiveSource.TORSO_KNEE] {
            guard let a = t.perspectiveIndex[source] else { continue }
            guard let b = c.perspectiveIndex[source] else { continue }
            return abs(b - a)
        }
        return nil
    }

    private static func pair(_ t: Double?, _ c: Double?, _ f: (Double, Double) -> Double?) -> Double? {
        guard let t = t, let c = c else { return nil }
        return f(t, c)
    }

    /// Chênh hướng mẫu, chọn nguồn theo lớp khung hình.
    ///
    /// Ảnh chân dung ưu tiên **góc MẶT** (chính xác ~3-5° so với ~8-10° của thân),
    /// ảnh toàn thân dùng **góc THÂN**.
    ///
    /// ⚠️ Chỉ dùng góc mặt khi **CẢ HAI BÊN** đều có. Trộn nguồn — mẫu đo bằng mặt,
    /// khung hình đo bằng thân — là phá bất biến "cùng một hàm": hai con số không
    /// so được với nhau, mà phép trừ vẫn ra kết quả trông hoàn toàn hợp lệ. Đúng
    /// loại lỗi không bao giờ lộ ra khi chạy thử.
    ///
    /// ⚠️ LUẬT "CHỈ SO KHI CÙNG ĐƯỜNG ĐO" — mục hướng mẫu trước đây THIẾU luật này.
    ///
    /// Bản cũ: ưu tiên góc mặt, nhưng **thiếu góc mặt ở một bên thì lặng lẽ lùi
    /// sang góc thân**. Hai đường đó có gốc 0 khác nhau — góc mặt đo đầu quay,
    /// góc thân đo đường vai. Người quay đầu mà giữ nguyên thân thì hai số lệch
    /// nhau hàng chục độ.
    ///
    /// Hậu quả: độ lệch **nhảy qua lại giữa hai thang** theo từng khung hình, nên
    /// mục này không bao giờ hội tụ. PO gặp đúng triệu chứng đó: *"máy bảo tôi
    /// xoay, nhưng tôi xoay mãi vẫn không đúng"*.
    ///
    /// Mục nghiêng ngang và mục ngửa/chúc đã có luật này từ lâu (xem `rollDeviation`,
    /// `pitchDeviation`). Mục hướng mẫu bị bỏ sót.
    ///
    /// Thiếu đường ưu tiên thì trả `nil` — không đo được, và tầng trên sẽ giải
    /// thích cho người dùng. Lùi sang đường khác là đo nhầm đại lượng.
    ///
    /// Cặp số đo cỡ mẫu (ảnh mẫu, khung hình) — chọn MỐC theo ảnh mẫu.
    ///
    /// Mốc chính của lớp khung hình (đầu→cổ chân…) bị bỏ khi chân chĩa vào ống
    /// kính, đúng ca ảnh chụp từ trên cao. Lúc đó dùng chiều cao khung mặt.
    ///
    /// ⚠️ Chọn theo ẢNH MẪU chứ không theo khung hình: ảnh mẫu cố định nên mốc
    /// không bao giờ đổi giữa chừng. Chọn theo cái nào đang có ở khung hiện tại là
    /// đúng lỗi FOOTGUNS 77 — độ lệch nhảy qua lại giữa hai thang.
    internal static func scalePair(_ t: PoseMeasurement, _ c: PoseMeasurement) -> (Double, Double)? {
        if let scale = t.scale {
            guard let cScale = c.scale else { return nil }
            return (scale, cScale)
        }
        if let faceScale = t.faceScale {
            guard let cFaceScale = c.faceScale else { return nil }
            return (faceScale, cFaceScale)
        }
        return nil
    }

    private static func yawDeviation(_ t: PoseMeasurement, _ c: PoseMeasurement) -> (YawSource, Double)? {
        switch t.framing.yawSource {
        case .faceYaw:
            if let tf = t.faceYawDeg, let cf = c.faceYawDeg {
                return (.faceYaw, angleDiff(tf, cf))
            }
            return nil
        case .body3D:
            if let ty = t.yawDeg, let cy = c.yawDeg {
                return (.body3D, angleDiff(ty, cy))
            }
            return nil
        }
    }

    /// Chênh lệch hai góc, luôn lấy đường ngắn nhất trên vòng tròn, kết quả 0..180.
    ///
    /// Không có phép này thì mẫu quay lưng ở −171° so với mẫu quay lưng ở +176° sẽ
    /// ra 347° — "lệch tối đa" — trong khi thực tế hai tư thế **gần như trùng nhau**
    /// (lệch 13°). Đúng đoạn video đã quay của dự án chạy qua vùng này.
    static func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = abs(a - b).truncatingRemainder(dividingBy: 360.0)
        if d > 180.0 { d = 360.0 - d }
        return d
    }

    /// Chênh dáng: trung bình độ lệch góc, chỉ tính nhóm CẢ HAI BÊN đều đo được và
    /// có cùng số khớp.
    private static func poseDiff(
        _ template: [PoseGroup: [Double]],
        _ candidate: [PoseGroup: [Double]]
    ) -> Double? {
        var sum = 0.0
        var n = 0
        for (group, tAngles) in template {
            guard let cAngles = candidate[group] else { continue }
            // Số khớp đo được có thể khác nhau giữa hai bên (một bên bị che tay).
            // Ghép "tới đâu hay tới đó" thì SAI: thứ tự lệch pha, so nhầm khớp này
            // với khớp kia, ra số vô nghĩa mà vẫn trông như số hợp lệ.
            if cAngles.count != tAngles.count { continue }
            for i in tAngles.indices {
                // NaN = khớp đó bên này không đo được (bị che, hoặc đang chĩa vào
                // ống kính như tay cầm máy khi selfie). Bỏ đúng cặp đó, giữ nguyên
                // các khớp còn lại — quy tắc số 4: không đo được KHÁC với sai.
                let t = tAngles[i]; let c = cAngles[i]
                if t.isNaN || c.isNaN { continue }
                sum += angleDiff(t, c)
                n += 1
            }
        }
        return n == 0 ? nil : sum / Double(n)
    }
}

/// TIÊU CHÍ HẬU KỲ: mép khung có cắt ngang khớp không.
///
/// Luật nhiếp ảnh cơ bản — cắt ngay tại cổ chân, đầu gối, cổ tay hay khuỷu làm chi
/// trông như bị cụt; cắt ở khoảng GIỮA hai khớp thì nhìn tự nhiên. Đây là thứ chỉ
/// đánh giá được **sau khi đã có ảnh**, nên không đưa vào hướng dẫn realtime: lúc
/// đang quay, khung hình đổi liên tục, nhắc điều này chỉ gây nhiễu.
nonisolated enum CropQuality {

    /// Khớp nằm trong dải này quanh mép khung thì coi như bị cắt ngang.
    private static let EDGE_BAND = 0.06

    /// Khớp nào đáng xét, tuỳ lớp khung hình.
    ///
    /// ⚠️ Phải lọc theo lớp khung hình. Ảnh bán thân thì cổ chân **đương nhiên** nằm
    /// ngoài khung — đó là chủ ý của bức ảnh, không phải lỗi cắt cụt. Xét bừa mọi
    /// khớp sẽ phạt oan mọi ảnh không phải toàn thân.
    static func jointsFor(_ framing: FramingClass) -> [Int] {
        switch framing {
        case .full:
            return [
                Lm.leftAnkle, Lm.rightAnkle, Lm.leftKnee, Lm.rightKnee,
                Lm.leftWrist, Lm.rightWrist, Lm.leftElbow, Lm.rightElbow,
            ]
        case .knee:
            return [
                Lm.leftKnee, Lm.rightKnee, Lm.leftWrist, Lm.rightWrist,
                Lm.leftElbow, Lm.rightElbow,
            ]
        case .half:
            return [
                Lm.leftWrist, Lm.rightWrist, Lm.leftElbow, Lm.rightElbow,
            ]
        case .chest:
            return [Lm.leftElbow, Lm.rightElbow]
        // Chân dung cận: không khớp nào đáng xét, mục này không áp dụng.
        case .head:
            return []
        }
    }

    static func appliesTo(_ framing: FramingClass) -> Bool { !jointsFor(framing).isEmpty }

    /// @return 1 = không khớp nào bị cắt ngang, 0 = mọi khớp đều nằm sát mép.
    ///         `nil` khi không có khớp nào để xét.
    static func of(_ frame: PoseFrame, _ framing: FramingClass, _ minVisibility: Float) -> Double? {
        if frame.isEmpty { return nil }
        let joints = jointsFor(framing)
        if joints.isEmpty { return nil }

        var atEdge = 0
        var counted = 0
        for i in joints {
            if i < 0 || i >= frame.points.count { continue }
            if frame.visibility[i] < minVisibility { continue }
            counted += 1
            let p = frame.points[i]
            let nearEdge = p.x <= EDGE_BAND || p.x >= 1.0 - EDGE_BAND ||
                p.y <= EDGE_BAND || p.y >= 1.0 - EDGE_BAND
            if nearEdge { atEdge += 1 }
        }
        if counted == 0 { return nil }
        return min(max(1.0 - Double(atEdge) / Double(counted), 0.0), 1.0)
    }
}
