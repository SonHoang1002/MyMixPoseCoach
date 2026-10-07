import Foundation

/// Hai chỗ dùng tới bộ tiêu chí, và chúng KHÁC NHAU.
///
/// Tách ra vì có những tiêu chí **chỉ chấm được sau khi đã có ảnh**, không thể đưa
/// vào hướng dẫn thời gian thực: bảo người cầm máy *"làm cho ảnh nét hơn"* là câu
/// vô nghĩa — họ không làm gì được với nó ngay lúc đó.
nonisolated enum Stage {
    /// Hướng dẫn thời gian thực trên màn camera — chỉ những gì người dùng SỬA ĐƯỢC NGAY.
    case GUIDANCE

    /// Chọn 5 ảnh sau khi quay — thêm các tiêu chí hậu kỳ.
    case SELECTION
}

/// MỘT TIÊU CHÍ CHẤM ĐIỂM.
///
/// ⚠️ ĐÂY LÀ CHỖ DUY NHẤT chứa trọng số và mốc quy đổi của toàn dự án. Trước đây
/// chúng nằm rải trong `ScoringConfig`, tách rời khỏi phần quyết định "tiêu chí nào
/// áp dụng" — hai thứ đó phải đi cùng nhau, nếu không sẽ có lúc chấm một mục mà
/// template không hề cần.
///
/// Hai loại số, ý nghĩa khác hẳn:
///  - [weight] — mục nào quan trọng hơn. Đây là quyết định SẢN PHẨM, buổi đo trên
///    máy thật không đổi được nó.
///  - [reference] — "lệch bao nhiêu thì coi như sai hoàn toàn". Cần có để cộng
///    được độ (góc) với tỉ lệ (khung hình) vào cùng một tổng. **Không phải** ngưỡng
///    đạt/không đạt.
nonisolated enum Criterion: CaseIterable {
    // =================================================================
    // ⚠️ THỨ TỰ KHAI BÁO Ở ĐÂY LÀ THỨ TỰ KIỂM VÀ THỨ TỰ NHẮC.
    //
    // `GuidanceEngine` sắp mục theo `ordinal`, nên đổi chỗ ở đây là đổi thứ tự
    // hướng dẫn. Sắp theo đúng tài liệu "Thứ tự kiểm khi camera đang mở":
    //
    //     1 hướng mẫu -> 2 xa/gần -> 3 máy cao/thấp -> 4 ngửa/chúc
    //     -> 5 trái/phải -> 6 dáng
    //
    // Lý do của thứ tự, trích tài liệu: *"Tiến/lùi làm đổi luôn kích thước mẫu
    // trong khung. Nâng/hạ máy làm đổi luôn góc ngửa/chúc cần thiết. Ngửa/chúc
    // làm mẫu trôi lên xuống trong khung. Nếu làm ngược thứ tự, bước sau sẽ phá
    // bước trước và người chụp phải làm lại mãi."*
    //
    // ⚠️ TRƯỚC 12/09/2026 `ROLL` ĐỨNG ĐẦU. Hậu quả đo được trên video test thật:
    // câu "đứng thẳng người lại, đang hơi ngả sang trái" chiếm 7/9 tới 9/11
    // khung hình, bịt kín kênh hướng dẫn — vì mỗi lúc app chỉ hiện MỘT câu.
    // Tay người luôn vẹo 1-3° nên mục này gần như không bao giờ tự tắt.
    // Nay xuống cuối: vẫn có tích, vẫn chấm điểm, nhưng chỉ lên tiếng khi 6 mục
    // kia đã xong.
    // =================================================================

    /// Tiêu chí cuối cùng và nhẹ nhất theo quyết định sản phẩm — không bao giờ chặn việc chụp.
    case YAW

    /// MỤC 7 — ZOOM & KHOẢNG CÁCH.
    ///
    /// Đo bằng **độ méo phối cảnh** (`Measurer.measurePerspective`) — đại lượng
    /// miễn nhiễm với zoom. Nó tách hai tình huống mà [SCALE] gộp làm một:
    ///
    /// - đi lại gần cho người vừa khung  ✅
    /// - đứng yên rồi **zoom vào** cho vừa khung  ❌ ảnh ra méo khác hẳn
    ///
    /// ⚠️ CHỈ ÁP DỤNG CHO ẢNH THẤY CHÂN. Quyết định sản phẩm 04/09/2026: **ảnh chân
    /// dung KHÔNG kiểm zoom** — ở lớp đó chỉ còn cái đầu để đo, mà đầu xoay tự do
    /// nên chỉ số bám theo tư thế đầu chứ không theo khoảng cách máy.
    ///
    /// [reference] 0,30: lệch quá mức này coi như sai hoàn toàn. Suy từ dải đo được
    /// (1m→4m chênh 0,133) nhân hệ số an toàn.
    case PERSPECTIVE
    case SCALE
    case ELEVATION

    /// MỤC 4 — MÁY NGỬA/CHÚC.
    ///
    /// Suy từ **độ méo phối cảnh**, không từ cảm biến: chúc máy xuống thì đầu vai
    /// trông to ra và chân ngắn lại; hất máy lên thì ngược lại. Xem
    /// `Measurer.measurePitchCue`.
    ///
    /// ⚠️ [reference] ở đây là **chỉ số không đơn vị**, không phải độ. 0,35 là con
    /// số PHỎNG ĐOÁN, chưa đo trên máy thật — đây là mục cần kiểm kỹ nhất trong
    /// buổi đo.
    case PITCH
    case CENTER
    case POSE

    // --- Các mục về VỊ TRÍ ĐẶT MÁY: dùng ở cả hai chỗ ---

    /// MỤC 8 — NGHIÊNG NGANG (vẹo chân trời).
    ///
    /// ⚠️ ĐẶT ĐẦU TIÊN CÓ CHỦ Ý. Máy nghiêng thì trục ngang và trục dọc CỦA ẢNH
    /// không còn trùng với trái/phải và trên/dưới của thế giới thật — mà mục
    /// [CENTER] và [ELEVATION] đo đúng theo hai trục đó. Sửa nghiêng trước thì hai
    /// mục kia mới sạch; sửa sau thì vừa chỉnh xong lại lệch lại.
    ///
    /// Trước đây app chỉ kiểm DỌC hay NGANG — một phép nhị phân 90°. Cầm máy vẹo
    /// 25° vẫn lọt, trong khi ảnh ra đã nghiêng thấy rõ.
    ///
    /// [reference] 25°: quá mức này thì bức ảnh nghiêng tới mức hỏng hẳn.
    case ROLL

    // --- HẬU KỲ: chỉ chấm khi chọn ảnh, KHÔNG đưa vào hướng dẫn ---

    /// Nhoè do CHỦ THỂ cử động. Không phải chấm chất lượng ảnh nói chung — người
    /// dùng đã chốt bỏ qua rung tay và ánh sáng.
    case SHARPNESS

    /// Mép khung cắt ngang tại khớp (cổ chân, gối, cổ tay, khuỷu).
    ///
    /// Luật nhiếp ảnh cơ bản: cắt ngay tại khớp làm chi trông như bị cụt. Chỉ có
    /// nghĩa ở bước chọn ảnh — lúc đang quay, khung hình đổi liên tục nên nhắc điều
    /// này chỉ gây nhiễu.
    case CROP

    /// HẬU KỲ — mẫu có nhắm mắt không.
    ///
    /// ⚠️ Đây là mục **không** nằm trong phần PO đã cắt scope. Bỏ qua ánh sáng và
    /// rung tay là quyết định sản phẩm; nhưng ảnh mẫu chớp mắt là ảnh hỏng, chẳng
    /// liên quan gì tới hai thứ đó. Bản iOS có (`eyesOpen`), bản Android trước đây
    /// thiếu.
    ///
    /// Trọng số nhỏ, đúng như iOS (0,06 trong nhóm chất lượng): nó là điểm trừ
    /// cuối cùng để phân định giữa những tấm đã ngang nhau, không phải tiêu chí chính.
    case EYES_OPEN

    // Sáu thông số khai báo trong enum của Kotlin (`key`, `label`, `weight`,
    // `reference`, `postOnly`, `groupLabel`) — giữ nguyên thứ tự và giá trị.
    private var spec: (
        key: String,
        label: String,
        weight: Double,
        reference: Double,
        postOnly: Bool,
        groupLabel: String
    ) {
        switch self {
        case .YAW: return ("huong", "Hướng mẫu", 3.0, 55.0, false, "")
        case .PERSPECTIVE: return ("zoom_khoangcach", "Chỗ đứng", 1.5, 0.30, false, "Khoảng cách & khung hình")
        case .SCALE: return ("xa_gan", "Khung hình", 3.0, 0.30, false, "Khoảng cách & khung hình")
        case .ELEVATION: return ("cao_thap", "Máy cao/thấp", 2.5, 35.0, false, "")
        case .PITCH: return ("ngua_chuc", "Máy ngửa/chúc", 2.0, 0.35, false, "")
        case .CENTER: return ("trai_phai", "Lệch trái/phải", 2.5, 0.22, false, "")
        case .POSE: return ("dang", "Dáng tay chân", 1.0, 55.0, false, "")
        case .ROLL: return ("nghieng_ngang", "Máy nghiêng", 2.5, 25.0, false, "")
        case .SHARPNESS: return ("do_net", "Độ nét", 2.0, 1.0, true, "")
        case .CROP: return ("cat_cut", "Cắt ngang khớp", 1.5, 1.0, true, "")
        case .EYES_OPEN: return ("mat_mo", "Mắt mở", 0.6, 1.0, true, "")
        }
    }

    var key: String { spec.key }

    var label: String { spec.label }

    /// Trọng số CƠ SỞ. Với năm mục hình học, con số thật lấy từ [weightFor] vì nó
    /// đổi theo lớp khung hình.
    var weight: Double { spec.weight }

    var reference: Double { spec.reference }

    /// `true` = chỉ chấm khi CHỌN ẢNH, không đưa vào hướng dẫn realtime.
    ///
    /// Dùng cờ thay vì tập hợp `Set<Stage>` vì tham số của enum **không truy cập
    /// được `companion object`** — hằng số dùng chung đặt ở đó sẽ báo lỗi biên dịch
    /// "companion object is uninitialized here".
    var postOnly: Bool { spec.postOnly }

    /// Tên hiển thị GỘP trên danh sách tích. Mặc định trùng [label].
    ///
    /// ⚠️ Vì sao cần: `SCALE` và `PERSPECTIVE` là **hai phép đo** khác nhau, nhưng
    /// với người dùng chỉ là **một câu hỏi** — *"tôi đứng đủ xa chưa?"*. Bày hai
    /// dòng riêng làm họ tưởng phải sửa hai thứ, trong khi thực tế là một việc có
    /// hai bước: đi bộ trước, zoom sau.
    ///
    /// Bên trong vẫn giữ hai mục riêng vì chúng đo hai thứ khác nhau và chấm điểm
    /// riêng — chỉ gộp ở tầng hiển thị.
    var groupLabel: String { spec.groupLabel }

    /// Mục này do NGƯỜI MẪU thực hiện, không phải người cầm máy.
    ///
    /// ⚠️ Dùng để (a) đánh dấu câu nhắc bằng biểu tượng loa — người cầm máy phải
    /// ĐỌC TO LÊN chứ không tự làm, và (b) đóng băng các mục về máy trong lúc đang
    /// nói, vì lúc đó họ hạ máy xuống và mọi mục về máy sẽ tuột.
    var forModel: Bool { self == .YAW || self == .POSE }

    /// Tên hiện trên danh sách tích — gộp nếu mục thuộc một nhóm.
    ///
    /// ⚠️ Trong Kotlin, các mục enum phải đứng TRƯỚC mọi thuộc tính, nên khai báo
    /// này bắt buộc nằm sau dấu `;`. Đặt lên trên là lỗi biên dịch.
    var displayLabel: String { groupLabel.isEmpty ? label : groupLabel }

    func appliesTo(_ stage: Stage) -> Bool { !postOnly || stage == .SELECTION }

    /// TRỌNG SỐ THẬT, ĐỔI THEO LỚP KHUNG HÌNH.
    ///
    /// ⚠️ Đây là điều bản Android trước đây làm thiếu: dùng **một bộ trọng số cho
    /// cả 5 lớp**, trong khi bản iOS đổi theo lớp. Xem cột `xa_gan`:
    ///
    /// ```
    /// toàn thân : yaw .26  cao/thấp .24  ngửa/chúc .20  xa/gần .16  trái/phải .14
    /// nửa người : yaw .24  cao/thấp .22  ngửa/chúc .20  xa/gần .19  trái/phải .15
    /// chân dung : yaw .22  cao/thấp .20  ngửa/chúc .16  xa/gần .24  trái/phải .18
    /// ```
    ///
    /// Xa/gần chỉ 0,16 với ảnh toàn thân nhưng **0,24 với ảnh chân dung — cao nhất
    /// nhóm**. Đúng vậy: chụp chân dung mà sai khoảng cách là hỏng ngay, còn ảnh
    /// toàn thân lệch một chút thì gần như không ai nhận ra.
    ///
    /// Bảng lấy từ `BestShotSelector.swift` của bản iOS, nhân 5,5 để giữ đúng tỉ lệ
    /// sản phẩm đã chốt: **hình học 0,55 · chất lượng 0,35 · dáng 0,10**.
    func weightFor(_ framing: FramingClass) -> Double {
        let f: Double
        switch self {
        case .YAW:
            switch framing {
            case .full, .knee: f = 0.26
            case .half: f = 0.24
            case .chest, .head: f = 0.22
            }
        case .ELEVATION:
            switch framing {
            case .full, .knee: f = 0.24
            case .half: f = 0.22
            case .chest, .head: f = 0.20
            }
        case .PITCH:
            switch framing {
            case .full, .knee, .half: f = 0.20
            case .chest, .head: f = 0.16
            }
        case .SCALE:
            switch framing {
            case .full, .knee: f = 0.16
            case .half: f = 0.19
            case .chest, .head: f = 0.24
            }
        case .CENTER:
            switch framing {
            case .full, .knee: f = 0.14
            case .half: f = 0.15
            case .chest, .head: f = 0.18
            }
        case .PERSPECTIVE:
            // Zoom & khoảng cách chỉ tồn tại ở lớp thấy chân, nên chỉ có hai mức.
            switch framing {
            case .full, .knee: f = 0.10
            // Không bao giờ tới đây: hồ sơ đã loại mục này ở các lớp kia.
            case .half, .chest, .head: f = 0.0
            }
        default:
            // Dáng và hai mục hậu kỳ không đổi theo lớp khung hình.
            return weight
        }
        return f * Criterion.GEOMETRY_TOTAL
    }

    /// Tổng trọng số của nhóm hình học. Dáng 1,0 + độ nét 2,0 + cắt cụt 1,5 = 4,5.
    static let GEOMETRY_TOTAL = 5.5
}

/// HỒ SƠ CỦA MỘT ẢNH MẪU — suy MỘT LẦN lúc chọn ảnh, dùng lại cho mọi khung hình.
///
/// Trả lời đúng câu hỏi: *"ảnh mẫu này cần chấm theo những tiêu chí nào?"*
///
/// ⚠️ PHÂN BIỆT HAI LOẠI "KHÔNG CHẤM", đây là lý do chính file này tồn tại:
///
/// | | Ví dụ | Xử lý |
/// |---|---|---|
/// | **Không áp dụng** (tính chất của template) | Ảnh chân dung cận → không bao giờ chấm về chân | Loại khỏi hồ sơ, **không bao giờ nhắc tới** |
/// | **Không đo được** (sự cố của một khung) | Khung này tình cờ không thấy hông | Bỏ riêng ở khung đó, các khung khác vẫn chấm |
///
/// Gộp hai thứ này là nguồn gốc của lỗi *"app bảo mẫu chỉnh chân trong khi đang
/// chụp chân dung"* — và ngược lại, *"app im lặng bỏ qua một mục đáng lẽ phải nhắc"*.
nonisolated struct TemplateProfile {
    var framing: FramingClass

    /// Số đo của chính ảnh mẫu. Mọi khung hình về sau đem so với cái này.
    var measurement: PoseMeasurement

    /// Những tiêu chí ảnh mẫu này ÁP DỤNG.
    var active: Set<Criterion>

    /// Tiêu chí bị loại, kèm lý do — để nói được cho người dùng, không im lặng bỏ.
    var skipped: [Criterion: String]

    /// Nhóm khớp được chấm ở mục dáng. Chân dung cận không có nhóm chân.
    var poseGroups: Set<PoseGroup>

    /// Kiểu chụp từ trên cao (gần 1x / góc rộng 0.5x / từ xa rồi zoom). Chỉ đổi câu
    /// nhắc khoảng cách/zoom. `nil` = không có nhãn — giữ cách cũ. Xem [KieuChupTren].
    var kieuChupTren: KieuChupTren? = nil

    /// Tiêu chí áp dụng ở một chỗ cụ thể. Hướng dẫn realtime ít mục hơn chọn ảnh.
    func activeFor(_ stage: Stage) -> Set<Criterion> {
        Set(active.filter { $0.appliesTo(stage) })
    }

    /// Mô tả bằng tiếng Việt cho người dùng đọc: sẽ chấm theo gì, bỏ qua gì và vì sao.
    /// Hiện ở hộp thoại cổng kiểm để người dùng biết trước khi vào màn camera.
    func describe() -> [String] {
        var out: [String] = []
        out.append("Kiểu khung hình: \(framing.displayName)")
        out.append(
            "Sẽ hướng dẫn theo \(activeFor(Stage.GUIDANCE).count) tiêu chí: " +
                activeFor(Stage.GUIDANCE).map { $0.label }.joined(separator: ", ")
        )
        for (c, why) in skipped { out.append("Bỏ qua \(c.label): \(why)") }
        return out
    }

    /// Suy hồ sơ từ ảnh mẫu đã nhận diện.
    ///
    /// Cách làm: **đo thử ảnh mẫu trước**, rồi mục nào ảnh mẫu không cung cấp
    /// nổi mốc so sánh thì loại khỏi hồ sơ. Không đoán theo tên lớp khung hình —
    /// đo thật rồi mới kết luận.
    ///
    /// Ảnh mẫu góc máy gắt từ mức này thì bỏ mục độ méo — xem FOOTGUNS 99. Nhãn góc chỉ
    /// có −35 / 0 / +25 nên mức nằm giữa 0 và 25 là tách đúng "trên/dưới" khỏi "ngang".
    static let GOC_GAT_DEG = 20.0

    private static let KHONG_NHAN_GOC =
        "ảnh mẫu chưa gắn nhãn góc máy (trên cao / ngang tầm / dưới thấp)"

    static func from(
        _ frame: PoseFrame,
        framing: FramingClass,
        minVisibility: Float,
        /// Số liệu khuôn mặt của ẢNH MẪU. `nil` = không thấy mặt hoặc chưa chạy.
        face: FaceInfo? = nil,
        /// Góc máy gán tay trong TÊN FILE ảnh mẫu, độ. Xem
        /// `MediaLibrary.gocMayTheoNhan`. `nil` = không có nhãn.
        ///
        /// Có nhãn thì nhãn THẮNG phép suy từ ảnh. Và nhờ nó mà ảnh selfie —
        /// vốn không suy được góc máy từ ảnh — có được mục 3 và mục 4.
        gocMayNhan: Double? = nil,
        /// Nhãn kiểu chụp từ trên cao. Xem [KieuChupTren].
        kieuChupTren: KieuChupTren? = nil
    ) -> TemplateProfile {
        let doAnh = Measurer.measure(frame, framing: framing, minVisibility: minVisibility, face: face)
        // ⚠️ GÓC MÁY CỦA ẢNH MẪU CHỈ LẤY TỪ NHÃN (16/09/2026) — FOOTGUNS 91.
        // Không nhãn thì bỏ hai mục góc máy (quy tắc số 4), không suy từ ảnh.
        let m: PoseMeasurement
        if let gocMayNhan = gocMayNhan {
            var copy = doAnh
            copy.tiltDeg = gocMayNhan
            var pitch = doAnh.pitchCue
            pitch[.GOC_MAY] = gocMayNhan
            copy.pitchCue = pitch
            copy.elevationDeg = Measurer.gocNhin(
                gocMayNhan, anchorY: doAnh.elevationAnchorY, vFovDeg: Measurer.VFOV_ANH_MAU
            )
            m = copy
        } else {
            m = doAnh.boGocMayTuAnh()
        }
        // ⚠️ ẢNH MẪU GÓC GẮT THÌ KHÔNG ĐO ĐỘ MÉO (19/09/2026) — FOOTGUNS 99.
        // Độ méo đo bằng tỉ lệ thân/chân trên ảnh. Chụp từ trên cao thì chân co
        // ngắn lại y như đứng gần; từ dưới thấp thì ngược lại. PO test ảnh chụp từ
        // trên cao mà đứng xa: app bảo "lùi thêm 1 bước" mãi.
        let gocGat = gocMayNhan.map({ abs($0) >= GOC_GAT_DEG }) ?? false
        var active = Set<Criterion>()
        var skipped = [Criterion: String]()

        func check(_ c: Criterion, _ ok: Bool, _ why: String) {
            if ok {
                active.insert(c)
            } else {
                skipped[c] = why
            }
        }

        check(
            .YAW, m.yawDeg != nil,
            "không thấy rõ hai vai trong ảnh mẫu nên không biết mẫu quay hướng nào"
        )
        check(
            // Mốc chính hỏng (chân chĩa vào ống kính) thì dùng khung mặt — xem
            // `PoseMeasurement.faceScale`.
            .SCALE, m.scale != nil || m.faceScale != nil,
            "không đo được \(framing.scaleAnchorLabel) trong ảnh mẫu nên không biết nên đứng xa hay gần"
        )
        check(
            .CENTER, m.centerX != nil,
            "không xác định được tâm chủ thể trong ảnh mẫu"
        )
        check(
            .ELEVATION, m.elevationDeg != nil,
            gocMayNhan == nil ? KHONG_NHAN_GOC : "người trong ảnh mẫu nằm lệch xa giữa khung hoặc không thấy mốc đo, nên không suy được máy cao hay thấp"
        )
        check(
            .ROLL, !m.rollDeg.isEmpty,
            "không thấy đủ vai (và hông) trong ảnh mẫu nên không biết ảnh có nghiêng không"
        )
        check(
            .PITCH, !m.pitchCue.isEmpty,
            gocMayNhan == nil ? KHONG_NHAN_GOC : "không đủ mốc để suy độ méo phối cảnh của ảnh mẫu " + "(cần thấy chân, hoặc thấy rõ mặt và hai vai)"
        )
        // ⚠️ HAI điều kiện, và phải xét theo đúng thứ tự này để câu giải thích
        // nói đúng nguyên nhân: lớp khung hình trước, rồi mới tới chuyện đo được.
        let whyPerspective: String
        if gocGat {
            whyPerspective = "ảnh mẫu chụp từ trên cao hoặc dưới thấp — góc máy làm thân/chân co giãn " +
                "y như đứng gần, không tách được khoảng cách. App đưa cả hai lựa chọn: " +
                "đi bộ hoặc zoom"
        } else if !framing.seesLegs {
            // ⚠️ KHÔNG nói "giữ zoom ở 1x" nữa. Câu đó mâu thuẫn thẳng với
            // lời nhắc realtime, vốn đưa cả hai lựa chọn đi bộ HOẶC zoom.
            whyPerspective = "ảnh mẫu là ảnh cận nên app không tự kiểm được zoom — " +
                "bạn được zoom thoải mái, nhưng hãy nhìn ảnh mẫu để tự chọn " +
                "đứng gần hay đứng xa rồi zoom"
        } else {
            whyPerspective = "không thấy rõ hông và chân trong ảnh mẫu nên không suy được độ méo phối cảnh"
        }
        check(
            .PERSPECTIVE,
            framing.seesLegs && !m.perspectiveIndex.isEmpty && !gocGat,
            whyPerspective
        )
        check(
            .POSE, !m.poseAngles.isEmpty,
            "không đo được khớp nào trong ảnh mẫu"
        )

        // Hậu kỳ chấm CHÍNH ẢNH CHỤP RA, không cần ảnh mẫu cung cấp mốc nào.
        active.insert(.SHARPNESS)
        active.insert(.EYES_OPEN)

        // Nhưng "cắt ngang khớp" thì phụ thuộc lớp khung hình: ảnh chân dung cận
        // không có khớp nào đáng xét, bật lên chỉ tổ phạt oan.
        check(
            .CROP, CropQuality.appliesTo(framing),
            "ảnh chân dung cận không có khớp tay chân nào để xét cắt cụt"
        )

        return TemplateProfile(
            framing: framing,
            measurement: m,
            active: active,
            skipped: skipped,
            poseGroups: framing.poseGroups,
            kieuChupTren: kieuChupTren
        )
    }
}

/// Tên nhóm khớp cho người thường đọc.
///
/// ⚠️ ĐÂY là chỗ trả lời trực tiếp yêu cầu *"ảnh chân dung thì không chấm về chân"*.
/// Nhóm khớp do lớp khung hình quyết định: `HEAD` chỉ có nhóm đầu, `CHEST` có đầu +
/// tay, chỉ `FULL` mới có chân. Hiện ra để người dùng thấy được điều đó, thay vì
/// phải tin lời hứa suông.
extension PoseGroup {
    var label: String {
        switch self {
        case .spine: return "thân"
        case .head: return "đầu"
        case .arms: return "tay"
        case .legs: return "chân"
        }
    }
}

/// Tên mốc đo tỉ lệ, viết cho người thường đọc.
nonisolated private extension FramingClass {
    var scaleAnchorLabel: String {
        switch self {
        case .full: return "khoảng đầu đến cổ chân"
        case .knee: return "khoảng đầu đến đầu gối"
        case .half: return "khoảng đầu đến hông"
        case .chest, .head: return "khung mặt"
        }
    }
}
