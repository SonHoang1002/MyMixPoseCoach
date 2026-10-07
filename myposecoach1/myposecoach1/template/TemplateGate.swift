import Foundation

/// CỔNG KIỂM ẢNH MẪU — 3 mức (TONG_QUAN_DU_AN.md §7.7).
///
/// Chạy NGAY LÚC CHỌN ẢNH, trước khi vào màn camera.
///
/// ⚠️ Lý do tồn tại: bản iOS cho vào màn camera với **mọi** ảnh, kể cả ảnh không
/// phân tích được — rồi đưa máy lên mẫu thì **không bao giờ có hướng dẫn nào**.
/// Ngõ cụt im lặng, người dùng không hiểu vì sao. Nguyên nhân đúng hai chỗ:
/// `ScreenImport.swift:170` (hàm phân tích rỗng) và `ScreenCamera.swift:441`
/// (`guard ... else { return }` lặng lẽ thoát).
///
/// Nguyên tắc nền: mức 🟡 tồn tại để **không từ chối oan** ảnh chỉ thiếu một tiêu
/// chí — đúng luật *"mục nào không đo được thì bỏ ra và chia lại trọng số, KHÔNG
/// trừ điểm"*. Mức 🔴 chỉ dành cho ảnh **không tính được gì cả**.
nonisolated enum TemplateVerdict {

    /// 🔴 Không cho vào màn camera.
    case Rejected(reason: String, hint: String)

    /// 🟡 Cho vào, nhưng phải báo trước những gì sẽ bị bỏ qua.
    case Accepted(framing: FramingClass, warnings: [String] = [])

    /// Chỉ có nghĩa với `.Accepted`; `.Rejected` trả `false`.
    var hasWarnings: Bool {
        switch self {
        case .Accepted(_, let warnings): return !warnings.isEmpty
        case .Rejected: return false
        }
    }
}

nonisolated enum TemplateGate {

    /// Ngưỡng tin cậy cho nhóm khớp LÕI (vai, hông) — thiếu là không tính được gì.
    ///
    /// Để public vì hồ sơ tiêu chí ([TemplateProfile]) phải suy bằng ĐÚNG ngưỡng mà
    /// cổng kiểm đã dùng. Hai ngưỡng khác nhau sẽ cho ra cảnh "cổng kiểm bảo đo
    /// được, hồ sơ bảo không".
    static let CORE_VIS: Float = 0.5

    /// Ngưỡng cho nhóm phụ (mặt, gối, cổ chân) — thiếu thì chỉ mất một tiêu chí.
    private static let AUX_VIS: Float = 0.4

    /// Chủ thể nhỏ hơn mức này thì mọi phép đo đều nhiễu nặng.
    private static let MIN_SUBJECT_HEIGHT = 0.25

    /// Chân có chĩa về phía ống kính không.
    ///
    /// Dùng đúng ngưỡng và đúng phép đo mà tầng đo dùng ([Measurer.MAX_OUT_OF_PLANE_DEG]),
    /// để cảnh báo hiện ra **đúng lúc** tiêu chí zoom bị bỏ — không lệch nhau.
    private static func legTowardLens(_ f: PoseFrame) -> Bool {
        guard let hip = midWorld(f, Lm.leftHip, Lm.rightHip) else { return false }
        guard let ankle = midWorld(f, Lm.leftAnkle, Lm.rightAnkle) else { return false }
        let flat = hypot(ankle[0] - hip[0], ankle[1] - hip[1])
        let depth = abs(ankle[2] - hip[2])
        let deg = flat < 1e-9 ? 90.0 : atan2(depth, flat) * 180.0 / Double.pi
        return deg > Measurer.MAX_OUT_OF_PLANE_DEG
    }

    private static func midWorld(_ f: PoseFrame, _ a: Int, _ b: Int) -> [Double]? {
        guard let A = f.world(a, minVisibility: CORE_VIS) else { return nil }
        guard let B = f.world(b, minVisibility: CORE_VIS) else { return nil }
        return [(A.x + B.x) / 2, (A.y + B.y) / 2, (A.z + B.z) / 2]
    }

    /// Ngưỡng độ nghiêng trục thân.
    ///
    /// ⚠️ CỐ Ý ĐỂ RỘNG. Phép đo này **luôn bị thổi phồng** khi ảnh chụp từ trên cao
    /// hoặc từ dưới thấp: phối cảnh nén chiều dọc của thân lại trong khi độ lệch
    /// ngang giữ nguyên, nên góc tính ra lớn hơn thực tế.
    ///
    /// Đã gặp thật: ảnh người **đứng tựa tường, chụp từ trên cao** cho ra ~49° và bị
    /// từ chối oan với ngưỡng 45° cũ. Mà tài liệu ghi rõ dáng tựa tường NẰM TRONG
    /// phạm vi hỗ trợ (Template B của tài liệu research có `spine_tilt` ~12°).
    ///
    /// Nên: chỉ TỪ CHỐI khi nghiêng tới mức gần như nằm ngang; khoảng giữa thì
    /// CẢNH BÁO và để người dùng tự quyết — đúng nguyên tắc "không từ chối oan".
    private static let REJECT_SPINE_TILT_DEG = 60.0
    private static let WARN_SPINE_TILT_DEG = 35.0

    /// @param frame kết quả phân tích ảnh mẫu, `nil` nghĩa là **không nạp được model**
    ///              (khác hẳn với "không thấy người" — phải phân biệt để báo đúng).
    static func check(_ frame: PoseFrame?) -> TemplateVerdict {
        guard let frame else {
            return TemplateVerdict.Rejected(
                reason: "Không phân tích được ảnh",
                hint: "Lỗi kỹ thuật của app, không phải do ảnh. Thử lại hoặc báo người phát triển."
            )
        }

        if frame.isEmpty {
            return TemplateVerdict.Rejected(
                reason: "Không tìm thấy người nào trong ảnh",
                hint: "Chọn ảnh có một người đứng, thấy rõ từ vai trở xuống."
            )
        }

        // --- Nhóm lõi: thiếu là không tính được tiêu chí nào ---
        let neck = frame.neck(minVisibility: CORE_VIS)
        let root = frame.root(minVisibility: CORE_VIS)

        // ⚠️ KHÔNG THẤY VAI THÌ VẪN NHẬN, NẾU THẤY MẶT (12/09/2026).
        //
        // Trước đây chỗ này TỪ CHỐI THẲNG với lý do "vai là mốc đo gốc của mọi
        // tiêu chí". Câu đó không còn đúng, và nó trái với nguyên tắc ghi ngay ở
        // đầu file này: *"mức 🔴 chỉ dành cho ảnh KHÔNG TÍNH ĐƯỢC GÌ CẢ"*.
        //
        // Bảng mốc đo theo lớp (tài liệu v3 mục 4) quy định lớp CHEST/HEAD dùng
        // **khuôn mặt** làm mốc cho cả ba việc: hướng mẫu (face yaw), xa/gần
        // (chiều cao khung mặt), lệch trái/phải (tâm khung mặt). Tài liệu còn ghi
        // rõ face yaw **chính xác hơn** phép suy từ vai (3-5° so với 8-10°).
        //
        // Nên ảnh khuất vai vẫn chấm được 3-4 mục. Từ chối là từ chối oan.
        let coMat = frame.at(Lm.nose, minVisibility: CORE_VIS) != nil &&
            (frame.at(Lm.leftEye, minVisibility: CORE_VIS) != nil ||
                frame.at(Lm.rightEye, minVisibility: CORE_VIS) != nil)

        if neck == nil && !coMat {
            return TemplateVerdict.Rejected(
                reason: "Không thấy rõ vai lẫn khuôn mặt của người trong ảnh",
                hint: "Cần thấy rõ HOẶC hai vai HOẶC khuôn mặt thì mới đo được. " +
                    "Chọn ảnh rõ phần thân trên hoặc rõ mặt."
            )
        }

        guard let box = frame.subjectBox(minVisibility: CORE_VIS) else {
            return TemplateVerdict.Rejected(
                reason: "Không đo được vị trí người trong khung",
                hint: "Chọn ảnh khác rõ hơn."
            )
        }

        if box.height < MIN_SUBJECT_HEIGHT {
            return TemplateVerdict.Rejected(
                reason: "Người trong ảnh quá nhỏ so với khung hình",
                hint: "Chọn ảnh chụp gần hơn, người chiếm ít nhất khoảng 1/4 chiều cao ảnh."
            )
        }

        // --- Dáng đứng: tài liệu chốt giai đoạn này CHỈ hỗ trợ dáng đứng ---
        let spineTilt = estimateSpineTiltDeg(frame)
        if let spineTilt, spineTilt > REJECT_SPINE_TILT_DEG {
            return TemplateVerdict.Rejected(
                reason: "Người trong ảnh gần như nằm ngang, không phải dáng đứng",
                hint: "Giai đoạn này chỉ hỗ trợ dáng ĐỨNG (kể cả tựa tường). " +
                    "Dáng ngồi hoặc nằm sẽ được hỗ trợ sau."
            )
        }

        guard let framing = FramingClass.detect(frame, minVisibility: CORE_VIS) else {
            return TemplateVerdict.Rejected(
                reason: "Không xác định được kiểu khung hình của ảnh",
                hint: "Chọn ảnh khác rõ hơn."
            )
        }

        // --- Từ đây trở xuống là NHẬN, chỉ cảnh báo những gì sẽ bị bỏ qua ---
        var warnings: [String] = []

        if neck == nil {
            warnings.append(
                "Không thấy rõ hai vai — app sẽ đo bằng khuôn mặt. " +
                    "Các mục cần vai (độ nghiêng máy, ngửa/chúc theo thân) sẽ bị bỏ qua."
            )
        }

        if let spineTilt, spineTilt > WARN_SPINE_TILT_DEG {
            warnings.append(
                String(format: "Trục thân nghiêng khoảng %.0f° so với phương thẳng đứng — ", spineTilt) +
                    "có thể do mẫu đang tựa, hoặc do ảnh chụp từ trên cao/dưới thấp. " +
                    "Nếu mẫu đang ngồi hoặc nằm thì hướng dẫn sẽ không chính xác."
            )
        }

        if root == nil {
            warnings.append(
                "Không thấy rõ hông — app sẽ đo tỉ lệ bằng khung mặt thay vì chiều cao thân."
            )
        }

        // --- Chi chĩa thẳng vào ống kính ---
        //
        // Ảnh mẫu kiểu "duỗi chân về phía máy" cho ra bàn chân to hơn cái đầu. Với
        // app thì đoạn hông→gót gần như trùng trục ống kính: chiều dài của nó trên
        // ảnh co về gần 0, mà công thức đo zoom lại CHIA cho chiều dài đó.
        //
        // Không từ chối — ảnh vẫn đẹp và 5 tiêu chí kia vẫn chạy. Nhưng phải nói
        // trước, vì hai thứ sẽ khác đi so với ảnh mẫu thường (quy tắc số 7).
        if framing.seesLegs && legTowardLens(frame) {
            warnings.append(
                "Ảnh mẫu có chân chĩa về phía ống kính — app sẽ bỏ qua tiêu chí zoom, " +
                    "và dáng này khó hướng dẫn cho mẫu làm theo bằng lời."
            )
        }

        // Lớp chân dung/bán thân lấy KHUNG MẶT làm mốc tỉ lệ và ĐƯỜNG MẮT làm mốc
        // góc nhìn. Không thấy mặt thì hai tiêu chí đó mất mốc.
        let seesFace = frame.at(Lm.nose, minVisibility: AUX_VIS) != nil ||
            frame.at(Lm.leftEye, minVisibility: AUX_VIS) != nil ||
            frame.at(Lm.rightEye, minVisibility: AUX_VIS) != nil
        if !seesFace && (framing == FramingClass.head || framing == FramingClass.chest) {
            warnings.append(
                "Ảnh chân dung nhưng không thấy rõ mặt — " +
                    "app sẽ bỏ qua tiêu chí xa/gần và máy cao/thấp."
            )
        }

        return TemplateVerdict.Accepted(framing: framing, warnings: warnings)
    }

    /// Độ nghiêng trục thân so với phương thẳng đứng, ĐỘ. 0 = thẳng đứng.
    ///
    /// Đo bằng **cả hai** cách rồi lấy **giá trị NHỎ HƠN**:
    ///  - Toạ độ 2 chiều trên ảnh — dễ hiểu nhưng bị phối cảnh thổi phồng
    ///  - Toạ độ 3 chiều thật (`worldLandmarks`) — có tính cả chiều sâu nên đỡ méo hơn
    ///
    /// Lấy giá trị nhỏ hơn là cố ý: phối cảnh chỉ có thể làm góc **lớn hơn** thực tế,
    /// không bao giờ nhỏ đi. Nên khi hai cách bất đồng, cách cho số nhỏ hơn gần sự
    /// thật hơn — và điều đó cũng đúng tinh thần "không từ chối oan".
    private static func estimateSpineTiltDeg(_ frame: PoseFrame) -> Double? {
        let neck2 = frame.neck(minVisibility: CORE_VIS)
        let root2 = frame.root(minVisibility: CORE_VIS)
        let tilt2d: Double?
        if let neck2, let root2 {
            let dy = abs(root2.y - neck2.y)
            tilt2d = dy < 1e-6 ? 90.0 : atan2(abs(neck2.x - root2.x), dy) * 180.0 / Double.pi
        } else {
            tilt2d = nil
        }

        let ls = frame.world(Lm.leftShoulder, minVisibility: CORE_VIS)
        let rs = frame.world(Lm.rightShoulder, minVisibility: CORE_VIS)
        let lh = frame.world(Lm.leftHip, minVisibility: CORE_VIS)
        let rh = frame.world(Lm.rightHip, minVisibility: CORE_VIS)
        let tilt3d: Double?
        if let ls, let rs, let lh, let rh {
            let nx = (ls.x + rs.x) / 2; let ny = (ls.y + rs.y) / 2; let nz = (ls.z + rs.z) / 2
            let hx = (lh.x + rh.x) / 2; let hy = (lh.y + rh.y) / 2; let hz = (lh.z + rh.z) / 2
            let dx = nx - hx; let dy = ny - hy; let dz = nz - hz
            let horizontal = hypot(dx, dz)
            tilt3d = abs(dy) < 1e-6 ? 90.0 : atan2(horizontal, abs(dy)) * 180.0 / Double.pi
        } else {
            tilt3d = nil
        }

        return [tilt2d, tilt3d].compactMap { $0 }.min()
    }
}
