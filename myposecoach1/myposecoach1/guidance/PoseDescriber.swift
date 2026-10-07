import Foundation

/// MÔ TẢ DÁNG CỦA ẢNH MẪU bằng vài câu ngắn 3-4 từ.
///
/// ## Dùng để làm gì
///
/// Hiện ở màn chọn ảnh mẫu, **TRƯỚC khi vào chụp**. Mẫu đọc rồi tự vào dáng gần
/// đúng; lúc chụp chỉ còn chỉnh nhỏ.
///
/// ⚠️ Đây là mấu chốt khiến hướng dẫn dáng khả thi. **Mẫu đứng cách máy 2-4m và
/// quay mặt về ống kính — họ KHÔNG nhìn được màn hình.** Mọi thứ hiện trên máy chỉ
/// người cầm máy thấy. Nên việc tạo dáng phải chuyển ra **trước lúc chụp**, bằng
/// lời; lúc chụp chỉ còn tinh chỉnh, mà tinh chỉnh thì nói bằng lời được.
///
/// ## Đã thử trên 28 ảnh thật trước khi viết
///
/// Tay, thân, chân đọc ra câu đúng và gọn. Riêng **ĐẦU thì bản thử SAI**: đo bằng
/// đoạn cổ→mũi thì cúi đầu cũng bị báo thành "nghiêng đầu", vì một đoạn thẳng không
/// tách được *cúi/ngẩng* khỏi *nghiêng*, và chiều trái/phải lúc đó lấy từ một độ
/// lệch ngang rất nhỏ — tức lấy nhiễu làm dấu.
///
/// Bản này sửa bằng cách tách hai phép đo riêng: **nghiêng** đọc từ độ dốc đường nối
/// hai tai, **cúi/ngẩng** đọc từ vị trí mũi so với đường tai.
///
/// ## Quy ước góc (giống `Measurer`)
///
/// `atan2(dx, dy)` với `dy` hướng XUỐNG: `0°` = chỉ xuống, `±90°` = chỉ ngang,
/// `180°` = chỉ lên. Góc khớp `0..180°`, `180°` = duỗi thẳng.
///
/// ⚠️ Trái/phải ở đây là **giải phẫu của mẫu**, không phải trái/phải trên ảnh.
/// MediaPipe đánh nhãn `left`/`right` theo cơ thể người đó, nên câu đọc lên cho
/// mẫu nghe luôn đúng dù hình có lật gương hay không.
nonisolated enum PoseDescriber {

    /// Mô tả dáng, mỗi câu 3-4 từ. Rỗng = không đủ mốc để mô tả.
    static func describe(_ frame: PoseFrame, minVis: Float) -> [String] {
        var out: [String] = []
        if let s = spine(frame, minVis: minVis) { out.append(s) }
        if let s = head(frame, minVis: minVis) { out.append(s) }
        if let s = arm(frame, minVis: minVis, left: true) { out.append(s) }
        if let s = arm(frame, minVis: minVis, left: false) { out.append(s) }
        if let s = leg(frame, minVis: minVis, left: true) { out.append(s) }
        if let s = leg(frame, minVis: minVis, left: false) { out.append(s) }
        return out
    }

    /// ĐỘ KHÓ của ảnh mẫu — để người dùng biết trước mình đang chọn cái gì.
    ///
    /// Gộp hai thứ:
    ///
    /// 1. **Dáng phải làm** — mỗi câu mô tả KHÁC tư thế mặc định (đứng thẳng, tay
    ///    buông) là một việc mẫu phải chủ động làm.
    /// 2. **Lớp khung hình** — ảnh càng cận thì dung sai đặt máy càng chặt.
    static func difficulty(_ frame: PoseFrame, framing: FramingClass, minVis: Float) -> Difficulty {
        let phrases = describe(frame, minVis: minVis)
        let chuDong = phrases.filter { $0 != "Đứng thẳng người" && !$0.hasSuffix("buông xuôi") }.count
        let khungHinh: Int
        switch framing {
        case .head, .chest: khungHinh = 2
        case .half: khungHinh = 1
        case .knee, .full: khungHinh = 0
        }
        switch chuDong + khungHinh {
        case 0, 1: return .de
        case 2, 3: return .trungBinh
        default: return .kho
        }
    }

    enum Difficulty {
        case de
        case trungBinh
        case kho

        var label: String {
            switch self {
            case .de: return "Dễ"
            case .trungBinh: return "Trung bình"
            case .kho: return "Khó"
            }
        }

        var hint: String {
            switch self {
            case .de: return "Đứng tự nhiên là được"
            case .trungBinh: return "Cần tạo dáng một chút"
            case .kho: return "Cần tạo dáng kỹ và đặt máy chính xác"
            }
        }
    }

    /// CÂU NHẮC CHỈNH DÁNG lúc chụp — chỉ **một khớp lệch nhất**, không đọc cả danh sách.
    ///
    /// ⚠️ Khác [describe] ở bản chất: [describe] mô tả ảnh mẫu để mẫu vào dáng
    /// TRƯỚC khi chụp; hàm này so ảnh mẫu với khung hình hiện tại và nói **việc phải
    /// sửa**.
    ///
    /// ⚠️ Chỉ đáng tin SAU KHI hướng mẫu đã khớp. Các góc này đo trên toạ độ 2 chiều
    /// của ảnh, nên mẫu xoay người là góc chiếu đổi dù dáng thật không đổi.
    static func correction(template: PoseFrame, live: PoseFrame, minVis: Float) -> String? {
        var worstDiff = 0.0
        var worstText: String? = nil
        func offer(_ diff: Double?, _ text: String) {
            guard let d = diff else { return }
            if d < noticeableDeg { return }
            if d > worstDiff {
                worstDiff = d
                worstText = text
            }
        }

        for left in [true, false] {
            let side = left ? "trái" : "phải"
            let sIdx = left ? Lm.leftShoulder : Lm.rightShoulder
            let eIdx = left ? Lm.leftElbow : Lm.rightElbow
            let wIdx = left ? Lm.leftWrist : Lm.rightWrist

            let tDir = upperArmDir(template, sIdx, eIdx, minVis)
            let lDir = upperArmDir(live, sIdx, eIdx, minVis)
            if let tDir, let lDir {
                offer(
                    abs(tDir - lDir),
                    lDir < tDir ? "Bảo mẫu giơ tay \(side) cao hơn" : "Bảo mẫu hạ tay \(side) xuống"
                )
            }

            let tEl = elbow(template, sIdx, eIdx, wIdx, minVis)
            let lEl = elbow(live, sIdx, eIdx, wIdx, minVis)
            if let tEl, let lEl {
                offer(
                    abs(tEl - lEl),
                    lEl < tEl ? "Bảo mẫu duỗi thẳng tay \(side) hơn" : "Bảo mẫu gập tay \(side) lại"
                )
            }
        }

        for left in [true, false] {
            let side = left ? "trái" : "phải"
            let tK = knee(template, left, minVis)
            let lK = knee(live, left, minVis)
            if let tK, let lK {
                offer(
                    abs(tK - lK),
                    lK < tK ? "Bảo mẫu duỗi thẳng chân \(side)" : "Bảo mẫu chùng gối \(side)"
                )
            }
        }

        let tS = spineAngle(template, minVis)
        let lS = spineAngle(live, minVis)
        if let tS, let lS { offer(abs(tS - lS), "Bảo mẫu chỉnh lại độ nghiêng người") }

        return worstText
    }

    private static func upperArmDir(_ f: PoseFrame, _ s: Int, _ e: Int, _ v: Float) -> Double? {
        guard let sh = f.at(s, minVisibility: v) else { return nil }
        guard let el = f.at(e, minVisibility: v) else { return nil }
        return segAngle(sh.x, sh.y, el.x, el.y).map { abs($0) }
    }

    private static func elbow(_ f: PoseFrame, _ s: Int, _ e: Int, _ w: Int, _ v: Float) -> Double? {
        guard let sh = f.at(s, minVisibility: v) else { return nil }
        guard let el = f.at(e, minVisibility: v) else { return nil }
        guard let wr = f.at(w, minVisibility: v) else { return nil }
        return jointAngle(sh.x, sh.y, el.x, el.y, wr.x, wr.y)
    }

    private static func knee(_ f: PoseFrame, _ left: Bool, _ v: Float) -> Double? {
        guard let h = f.at(left ? Lm.leftHip : Lm.rightHip, minVisibility: v) else { return nil }
        guard let k = f.at(left ? Lm.leftKnee : Lm.rightKnee, minVisibility: v) else { return nil }
        guard let a = f.at(left ? Lm.leftAnkle : Lm.rightAnkle, minVisibility: v) else { return nil }
        return jointAngle(h.x, h.y, k.x, k.y, a.x, a.y)
    }

    private static func spineAngle(_ f: PoseFrame, _ v: Float) -> Double? {
        guard let neck = f.neck(minVisibility: v) else { return nil }
        guard let root = f.root(minVisibility: v) else { return nil }
        return segAngle(neck.x, neck.y, root.x, root.y)
    }

    /// Lệch dưới mức này thì KHÔNG nhắc.
    ///
    /// Bảo người ta "nâng tay lên 8 độ" là câu không ai làm được, nghe xong chỉ thấy
    /// app khó tính. Cùng tinh thần với `Band.actionFloor` của các mục kia.
    private static let noticeableDeg = 20.0

    // -----------------------------------------------------------------

    private static func spine(_ f: PoseFrame, minVis v: Float) -> String? {
        guard let neck = f.neck(minVisibility: v) else { return nil }
        guard let root = f.root(minVisibility: v) else { return nil }
        guard let a = segAngle(neck.x, neck.y, root.x, root.y) else { return nil }
        // root nằm DƯỚI neck nên góc quanh 0 khi đứng thẳng.
        if abs(a) < spineStraightDeg { return "Đứng thẳng người" }
        // a > 0 = hông lệch sang phải ẢNH = mẫu nghiêng sang TRÁI của họ.
        return a > 0 ? "Nghiêng người sang trái" : "Nghiêng người sang phải"
    }

    /// ⚠️ HAI phép đo riêng, không gộp làm một.
    ///
    /// Bản thử đầu dùng đoạn cổ→mũi cho cả hai và **sai**: cúi đầu bị báo thành
    /// nghiêng đầu ở gần như mọi ảnh thử.
    private static func head(_ f: PoseFrame, minVis v: Float) -> String? {
        let le = f.at(Lm.leftEar, minVisibility: v)
        let re = f.at(Lm.rightEar, minVisibility: v)
        guard let nose = f.at(Lm.nose, minVisibility: v) else { return nil }

        // Không thấy đủ hai tai (mũ che, quay nghiêng) thì KHÔNG đoán bừa.
        guard let le, let re else { return nil }
        let earSpan = hypot(le.x - re.x, le.y - re.y)
        if earSpan < 1e-4 { return nil }

        // NGHIÊNG: độ dốc của đường nối hai tai.
        let roll = atan2(le.y - re.y, le.x - re.x) * 180.0 / Double.pi
        let rollDeg = abs(roll) > 90 ? 180 - abs(roll) : abs(roll)
        if rollDeg >= headRollDeg {
            return roll > 0 ? "Nghiêng đầu sang trái" : "Nghiêng đầu sang phải"
        }

        // CÚI/NGẨNG: mũi cao thấp so với đường tai, đo theo bề ngang đầu để không
        // phụ thuộc mẫu đứng xa hay gần.
        let earMidY = (le.y + re.y) / 2.0
        let nod = (nose.y - earMidY) / earSpan
        if nod > headNodRatio { return "Hơi cúi đầu xuống" }
        if nod < -headNodRatio { return "Hơi ngẩng đầu lên" }
        return nil   // đầu thẳng thì không cần nói gì
    }

    private static func arm(_ f: PoseFrame, minVis v: Float, left: Bool) -> String? {
        let sIdx = left ? Lm.leftShoulder : Lm.rightShoulder
        let eIdx = left ? Lm.leftElbow : Lm.rightElbow
        let wIdx = left ? Lm.leftWrist : Lm.rightWrist
        let side = left ? "trái" : "phải"

        guard let sh = f.at(sIdx, minVisibility: v) else { return nil }
        guard let el = f.at(eIdx, minVisibility: v) else { return nil }
        guard let dir = segAngle(sh.x, sh.y, el.x, el.y).map({ abs($0) }) else { return nil }

        // Hướng cánh tay TRÊN: 0 = buông thẳng xuống, 90 = dang ngang, 180 = giơ lên.
        let huong: String
        if dir < 30 { huong = "buông xuôi" }
        else if dir < 70 { huong = "hơi dang ra" }
        else if dir < 115 { huong = "dang ngang" }
        else { huong = "giơ lên" }

        // Khuỷu gập hay không — chỉ nói thêm khi thật sự gập.
        let wr = f.at(wIdx, minVisibility: v)
        let elbowAngle = wr != nil ? jointAngle(sh.x, sh.y, el.x, el.y, wr!.x, wr!.y) : nil
        let gap = elbowAngle != nil && elbowAngle! < elbowBentDeg
        if gap && dir < 70 { return "Tay \(side) gập lại" }
        if gap { return "Tay \(side) \(huong), gập khuỷu" }
        return "Tay \(side) \(huong)"
    }

    private static func leg(_ f: PoseFrame, minVis v: Float, left: Bool) -> String? {
        guard let h = f.at(left ? Lm.leftHip : Lm.rightHip, minVisibility: v) else { return nil }
        guard let k = f.at(left ? Lm.leftKnee : Lm.rightKnee, minVisibility: v) else { return nil }
        guard let a = f.at(left ? Lm.leftAnkle : Lm.rightAnkle, minVisibility: v) else { return nil }
        guard let ang = jointAngle(h.x, h.y, k.x, k.y, a.x, a.y) else { return nil }
        // Chân duỗi thẳng là mặc định, không cần nói. Chỉ nói khi chùng rõ.
        return ang < kneeBentDeg ? "Chùng gối \(left ? "trái" : "phải")" : nil
    }

    // -----------------------------------------------------------------

    private static func segAngle(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double? {
        let dx = bx - ax
        let dy = by - ay
        if hypot(dx, dy) < 1e-6 { return nil }
        return atan2(dx, dy) * 180.0 / Double.pi
    }

    private static func jointAngle(
        _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double
    ) -> Double? {
        let v1x = ax - bx; let v1y = ay - by
        let v2x = cx - bx; let v2y = cy - by
        let n1 = hypot(v1x, v1y); let n2 = hypot(v2x, v2y)
        if n1 < 1e-6 || n2 < 1e-6 { return nil }
        let cos = min(max((v1x * v2x + v1y * v2y) / (n1 * n2), -1.0), 1.0)
        return acos(cos) * 180.0 / Double.pi
    }

    // Các mốc dưới đây chọn từ 28 ảnh thử. Chúng quyết định câu chữ chứ không
    // quyết định điểm số, nên chỉnh thoải mái theo cảm nhận người đọc.
    private static let spineStraightDeg = 10.0
    private static let headRollDeg = 12.0
    private static let headNodRatio = 0.45
    private static let elbowBentDeg = 110.0
    private static let kneeBentDeg = 160.0
}
