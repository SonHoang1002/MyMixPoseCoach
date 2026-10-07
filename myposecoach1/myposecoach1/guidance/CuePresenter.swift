import Foundation

/// Trạng thái một mục ở một khung hình, đủ dữ liệu để vừa vẽ danh sách tích vừa
/// viết được lời nhắc.
nonisolated struct CriterionStatus {
    let criterion: Criterion
    var state: GateState

    /// Độ lệch TUYỆT ĐỐI so với ảnh mẫu. `nil` = khung này không đo được.
    let deviation: Double?

    /// Hiệu CÓ DẤU (khung hình trừ ảnh mẫu) — chỉ dùng để **chọn chữ**, không dùng
    /// để chấm điểm.
    ///
    /// Tách khỏi [deviation] vì chấm điểm chỉ quan tâm lệch bao nhiêu, còn lời nhắc
    /// bắt buộc phải biết lệch về phía nào mới nói được "lùi lại" hay "tiến lên".
    let signedDelta: Double?

    let band: Band?

    /// Quãng đường cần đi, MÉT. Chỉ có ở mục chỗ đứng và mục khung hình khi phải
    /// đi bộ. `nil` = không ước lượng được, câu sẽ lùi về "một chút".
    var moveMeters: Double? = nil

    /// Mục khung hình phải nói ĐI BỘ thay vì ZOOM.
    ///
    /// Bật khi ảnh mẫu KHÔNG có bước khoảng cách (ảnh cận, chân chĩa vào máy, ảnh mẫu
    /// chụp từ trên cao/dưới thấp): app không biết người dùng đứng sai chỗ hay zoom
    /// sai, nên câu đưa cả hai lựa chọn đi bộ hoặc zoom.
    var walkInsteadOfZoom: Bool = false

    /// Câu nhắc chỉnh dáng theo khớp lệch nhất. Chỉ có ở mục dáng.
    var poseHint: String? = nil

    /// MỤC NGHIÊNG NGANG — cảm biến nói lỗi nằm ở MÁY hay ở MẪU.
    ///
    /// `true`  = máy đang thật sự vẹo → bảo người cầm máy xoay lại
    /// `false` = máy đang thẳng, nhưng ảnh vẫn nghiêng → lỗi ở dáng của mẫu
    ///
    /// ⚠️ Đây là chỗ DUY NHẤT trong app dùng cảm biến để hướng dẫn, và nó **không
    /// tham gia chấm điểm** — chấm vẫn đo từ ảnh ở cả hai bên. Cảm biến chỉ trả lời
    /// câu "nhắc ai", thứ mà ảnh không tự trả lời được.
    var rollFromDevice: Bool = true

    /// Mục 3 đã GỘP với mục 4 vì hai mục cùng chiều — câu nhắc nói cả hai động tác.
    /// Xem `GuidanceEngine.gopCaoVaChuc`.
    var kemChuc: Bool = false

    /// Góc máy của ẢNH MẪU, độ — chỉ đặt cho mục ngửa/chúc khi ảnh mẫu KHÔNG có
    /// mục máy cao/thấp. Xem nhánh `Criterion.PITCH` trong `cueTextFor`.
    var gocMauKhongCoCaoThap: Double? = nil

    /// Mục này ÁP DỤNG cho ảnh mẫu nhưng khung hình hiện tại **không đo được**, và
    /// đã như vậy đủ lâu để cần giải thích.
    ///
    /// ⚠️ Khác hẳn "chưa đạt": không có gì sai để sửa cho đúng, mà là app đang
    /// **không nhìn thấy đủ** để chấm. Người dùng thấy một dấu gạch nằm im mãi và
    /// không hiểu vì sao — ngõ cụt im lặng, quy tắc số 7 cấm.
    var unmeasuredTooLong: Bool = false

    /// Người cầm máy CHÍNH LÀ mẫu, và họ nhìn thấy màn hình.
    /// Bỏ tiền tố *"Bảo mẫu…"* — không có ai để bảo. Xem [ShootMode].
    var tuChup: Bool = false

    /// Hình đang xem bị LẬT NGANG (chụp qua gương, hoặc camera trước lưu ảnh lật).
    /// ⚠️ CHỈ ĐẢO CHỮ TRÁI/PHẢI TRONG CÂU NHẮC DÁNG. Không đụng tới phép đo.
    var latGuong: Bool = false

    /// Dịch máy trên màn hình NGƯỢC CHIỀU camera thường (camera trước).
    var mayNguocChieu: Bool = false

    /// Khoảng cách chỉnh bằng co/duỗi TAY, không phải bằng bước chân.
    var tamTay: Bool = false

    /// Chưa tới lượt xử lý vì một bước trước trong quy trình chưa xong.
    var pending: Bool = false

    /// Đã thử đủ lâu trong chế độ tự động nhưng không hội tụ; cho phép đi tiếp.
    var skipped: Bool = false

    /// Mức zoom đề nghị sau khi chỗ đứng đã được khoá.
    var targetZoom: Float? = nil

    /// Ảnh mẫu chụp từ trên cao, đứng gần: zoom không được vượt mức này (1x). Xem `KieuChupTren`.
    var zoomToiDa: Float? = nil

    /// Máy đang zoom vào quá [zoomToiDa].
    var zoomSai: Bool = false

    /// Máy có ống góc rộng (zoom ra dưới 1x được) — mới gợi ý kiểu mắt cá.
    var coGocRong: Bool = false

    /// Ảnh mẫu chụp từ trên cao, đứng xa rồi zoom.
    var chupTuXa: Bool = false

    /// Đã đứng đủ xa (theo ước lượng) cho kiểu chụp từ xa.
    var duXa: Bool = false

    /// Câu của mục này, TRONG khung hình này, là câu để ĐỌC TO CHO MẪU NGHE.
    ///
    /// ⚠️ Không dùng thẳng `criterion.forModel` được: đó là thuộc tính tĩnh của
    /// LOẠI mục, mà mục nghiêng ngang lại đổi vai theo từng khung hình.
    var isModelCue: Bool { criterion.forModel }

    /// Số bước để ghép vào câu. Không ước lượng được thì nói "một chút".
    func stepsPhrase() -> String {
        moveMeters.map { DistanceEstimator.stepsPhrase($0) } ?? "một chút"
    }

    /// Lệch gấp mấy lần ngưỡng đạt. Dùng để chọn mức độ của câu chữ.
    var severity: Double? {
        guard let d = deviation, let a = band?.accept else { return nil }
        guard a > 0.0 else { return nil }
        return d / a
    }
}

/// BỘ CHỌN LỜI NHẮC — mỗi lúc đúng MỘT câu.
///
/// Bốn luật, mỗi luật chữa một cách làm người dùng hoang mang:
///
/// | Luật | Chữa gì |
/// |---|---|
/// | Mỗi lúc 1 câu | đọc 3 câu cùng lúc thì không làm được câu nào |
/// | Câu đã hiện ở lại tối thiểu 1,2 giây | chữ nhảy nhanh hơn mắt đọc |
/// | Số trong câu chỉ đổi 1 lần/giây | "xoay 7 độ" thành "xoay 9 độ" rồi "xoay 6 độ" trong một giây |
/// | Đóng băng khi lắc mạnh | đang đưa máy thì mọi số đều vô nghĩa |
nonisolated final class CuePresenter {

    private var currentCriterion: Criterion?
    private var currentText: String?
    private var shownAtMs: Int64 = 0
    private var numberRefreshedAtMs: Int64 = 0

    /// - Parameter failing các mục đang FAILING, **đã lọc và đã sắp theo thứ tự ưu tiên**
    ///        (thứ tự khai báo trong [Criterion]: hướng mẫu trước, dáng cuối cùng).
    /// - Parameter angularSpeedDegPerSec tốc độ quay của máy, để biết có đang lắc không.
    /// - Returns câu cần hiện, `nil` = không nhắc gì.
    func update(failing: [CriterionStatus],
                nowMs: Int64,
                angularSpeedDegPerSec: Double) -> String? {
        // Đang lắc mạnh: giữ nguyên câu đang hiện, không đổi chữ cũng không đổi số.
        if angularSpeedDegPerSec > GuidanceTiming.FREEZE_CUE_ANGULAR_SPEED_DEG_PER_SEC {
            return currentText
        }

        guard let top = failing.first else {
            currentCriterion = nil
            currentText = nil
            return nil
        }

        let current = currentCriterion
        let heldLongEnough = nowMs - shownAtMs >= GuidanceTiming.CUE_MIN_DISPLAY_MS
        let currentStillFailing = failing.contains { $0.criterion == current }

        let chosen: CriterionStatus
        if let current {
            // ⚠️ ĐÃ GỠ LUẬT "mục ưu tiên cao hơn chen ngang ngay".
            //
            // Ý định ban đầu hợp lý: mục quan trọng hơn thì nói ngay, không phải
            // chờ hết 1,2 giây. Nhưng trên máy thật nó thành **máy sinh nhấp nháy**:
            // `failing` xếp theo thứ tự khai báo, mà mục đứng đầu (nghiêng máy,
            // chỗ đứng) lại là mấy mục **nhạy nhất với rung tay**. Mỗi lần vào là
            // chen ngang, đá văng câu đang hiện — chữ nhảy loạn.
            //
            // Việc "sửa máy trước, sửa mẫu sau" vẫn được bảo đảm ở tầng trên
            // (`GuidanceEngine` lọc danh sách ứng viên), không cần chen ngang ở đây.
            if !currentStillFailing {
                chosen = top
            } else if !heldLongEnough {
                chosen = failing.first { $0.criterion == current }!
            } else {
                chosen = top
            }
        } else {
            chosen = top
        }

        if chosen.criterion != currentCriterion {
            currentCriterion = chosen.criterion
            currentText = cueTextFor(chosen)
            shownAtMs = nowMs
            numberRefreshedAtMs = nowMs
            return currentText
        }

        // Cùng một mục: chỉ cho phép chữ đổi mỗi giây một lần, nếu không con số
        // trong câu sẽ nhảy theo từng khung hình.
        if nowMs - numberRefreshedAtMs >= GuidanceTiming.CUE_NUMBER_REFRESH_MS {
            currentText = cueTextFor(chosen)
            numberRefreshedAtMs = nowMs
        }
        return currentText
    }

    func reset() {
        currentCriterion = nil
        currentText = nil
        shownAtMs = 0
        numberRefreshedAtMs = 0
    }
}

// MARK: - Viết câu nhắc

/// "1x", "0.5x" — không kèm số lẻ thừa.
nonisolated private func nhanZoom(_ z: Float) -> String {
    let r = z.rounded()
    if z == r { return "\(Int(r))x" }
    return String(format: "%.1f", Double(z)) + "x"
}

/// Ảnh mẫu chúc/ngửa gắt từ mức này trở lên thì máy buộc phải đổi độ cao, không chỉ đổi góc.
nonisolated private let GOC_GAT_DEG = 20.0

/// ⚠️ HAI LUẬT VỀ CÂU CHỮ:
///
/// 1. **Câu về DÁNG viết theo góc nhìn của NGƯỜI MẪU**, vì người cầm máy sẽ đọc to
///    lên cho mẫu nghe. Viết theo góc nhìn màn hình là lộn trái-phải.
/// 2. **Câu về HƯỚNG MẪU phải nói đúng chiều đã kiểm chứng** — góc dương = mẫu quay
///    về phía TRÁI CỦA HỌN.
///
/// Các câu về VỊ TRÍ MÁY nói trái/phải được, vì màn chụp dùng **camera sau** nên
/// hình không bị lật gương.
nonisolated func cueTextFor(_ status: CriterionStatus) -> String {
    let signed = status.signedDelta ?? 0.0

    // ⚠️ XÉT TRƯỚC MỌI CÂU KHÁC: không đo được thì KHÔNG CÓ GÌ để sửa cho đúng.
    if status.unmeasuredTooLong {
        var text: String
        switch status.criterion {
        case .PERSPECTIVE:
            text = "Chưa kiểm được zoom — lùi ra một chút cho thấy đầu gối"
        case .SCALE:
            text = "Chưa đo được khung hình — lùi ra cho thấy đủ người như ảnh mẫu"
        case .ROLL, .CENTER, .ELEVATION:
            text = "Chưa thấy rõ vai và hông — lùi ra hoặc chỉnh cho người vào giữa khung"
        case .PITCH:
            text = "Chưa đo được góc máy — lùi ra cho thấy rõ mặt và hai vai"
        case .YAW:
            text = "Chưa nhìn rõ hướng của mẫu — lùi ra cho thấy rõ phần thân trên"
        case .POSE:
            text = "Chưa thấy rõ tay chân của mẫu để so dáng"
        default:
            text = "Chưa đo được mục này — lùi ra cho thấy đủ người"
        }
        // Tự chụp cầm tay thì không lùi được — khoảng cách là độ duỗi TAY.
        if status.tamTay {
            text = text.replacingOccurrences(of: "lùi ra", with: "duỗi tay ra xa")
        }
        return text
    }

    var out: String
    switch status.criterion {
    case .YAW:
        // ⚠️ Viết theo GÓC NHÌN CỦA MẪU, vì người cầm máy đọc to câu này lên.
        let lech = abs(signed)
        let cau: String
        if lech > 120.0 {
            cau = "quay hẳn người lại, đang ngược hướng ảnh mẫu"
        } else if signed > 0 {
            cau = "xoay người sang phải từ từ đến khi tích sáng"
        } else {
            cau = "xoay người sang trái từ từ đến khi tích sáng"
        }
        let day = status.tuChup ? cau.firstLetterUppercased() : "Bảo mẫu " + cau
        out = doiBenNeuLatGuong(day, status.latGuong)

    case .ROLL:
        // ⚠️ XOAY THÌ KHÁC HẲN DỊCH NGANG — đừng gộp hai cái làm một.
        // Dịch ngang có HAI lần đảo nên triệt tiêu; xoay chỉ có MỘT.
        let s2 = status.mayNguocChieu ? -signed : signed
        // ⚠️ LUÔN NÓI VỀ MÁY, KHÔNG ĐỔ CHO MẪU NỮA (14/09/2026).
        out = s2 > 0
            ? "Xoay máy ngược chiều kim đồng hồ đến khi tích sáng"
            : "Xoay máy theo chiều kim đồng hồ đến khi tích sáng"

    case .PERSPECTIVE:
        if status.tamTay && signed > 0 {
            out = "Duỗi tay ra xa từ từ đến khi tích sáng"
        } else if status.tamTay {
            out = "Co tay lại gần từ từ đến khi tích sáng"
        } else if signed > 0 {
            out = "Lùi lại " + status.stepsPhrase()
        } else {
            out = "Tiến lên " + status.stepsPhrase()
        }

    case .SCALE:
        // KHUNG HÌNH — tới đây thì chỗ đứng đã đúng (PERSPECTIVE ưu tiên cao hơn),
        // nên việc còn lại chỉ là zoom.
        if let zMax = status.zoomToiDa, status.zoomSai {
            out = "Đưa zoom về \(nhanZoom(zMax)) hoặc nhỏ hơn đến khi tích sáng"
        } else if status.zoomToiDa != nil, signed > 0 {
            out = "Lùi lại " + status.stepsPhrase()
        } else if status.zoomToiDa != nil, status.coGocRong {
            out = "Tiến sát vào " + status.stepsPhrase() +
                " — giữ 1x, hoặc zoom ra 0.5–0.7x nếu muốn kiểu mắt cá"
        } else if status.zoomToiDa != nil {
            out = "Tiến sát vào " + status.stepsPhrase() + ", giữ zoom 1x"
        } else if status.chupTuXa && !status.duXa {
            out = "Lùi ra xa thêm " + status.stepsPhrase() + ", rồi zoom vào"
        } else if status.chupTuXa, let tz = status.targetZoom {
            let muc = String(format: "%.1f", Double(tz))
            out = "Đặt zoom khoảng \(muc)x đến khi tích sáng"
        } else if status.tamTay && signed > 0 {
            out = "Duỗi tay ra xa từ từ đến khi tích sáng"
        } else if status.tamTay {
            out = "Co tay lại gần từ từ đến khi tích sáng"
        } else if status.walkInsteadOfZoom {
            out = signed > 0
                ? "Lùi lại " + status.stepsPhrase() + ", hoặc zoom ra từ từ đến khi tích sáng"
                : "Tiến lên " + status.stepsPhrase() + ", hoặc zoom vào từ từ đến khi tích sáng"
        } else if let tz = status.targetZoom {
            let muc = String(format: "%.1f", Double(tz))
            out = "Đặt zoom khoảng \(muc)x đến khi tích sáng"
        } else if signed > 0 {
            out = "Zoom ra từ từ đến khi tích sáng"
        } else {
            out = "Zoom vào từ từ đến khi tích sáng"
        }

    case .CENTER:
        // Camera sau nên hình KHÔNG bị lật gương. Dịch máy về phía BÊN PHẢI CỦA
        // KHUNG HÌNH -> cảnh chạy sang TRÁI — đúng ở cả ba chế độ (hai lần đảo
        // của camera trước triệt tiêu nhau, gương là cảnh tĩnh).
        out = signed > 0
            ? "Đưa máy sang phải từ từ đến khi tích sáng"
            : "Đưa máy sang trái từ từ đến khi tích sáng"

    case .ELEVATION:
        // `elevationDeg` âm = máy đang trên cao chúc xuống. `signed` = live trừ mẫu.
        // signed > 0 nghĩa là tia của ta đang ngång hơn ảnh mẫu → máy đang THẤP hơn
        // cần thiết → phải nâng lên.
        if status.kemChuc && signed > 0 {
            out = "Nâng máy cao hơn rồi chúc xuống, đến khi tích sáng"
        } else if status.kemChuc {
            out = "Hạ máy thấp xuống rồi hất lên, đến khi tích sáng"
        } else if signed > 0 {
            out = "Nâng máy lên cao hơn, giữ nguyên góc, đến khi tích sáng"
        } else {
            out = "Hạ máy xuống thấp hơn, giữ nguyên góc, đến khi tích sáng"
        }

    case .PITCH:
        // ẢNH MẪU GÓC GẮT MÀ KHÔNG CÓ MỤC MÁY CAO/THẤP (14/09/2026).
        let g = status.gocMauKhongCoCaoThap
        if let g, g <= -GOC_GAT_DEG && signed > 0 {
            out = "Nâng máy cao hơn rồi chúc xuống, đến khi tích sáng"
        } else if let g, g >= GOC_GAT_DEG && signed < 0 {
            out = "Hạ máy thấp xuống rồi hất lên, đến khi tích sáng"
        } else if signed > 0 {
            out = "Chúc máy xuống thêm một chút, đến khi tích sáng"
        } else {
            out = "Hất máy lên thêm một chút, đến khi tích sáng"
        }

    case .POSE:
        // Mục cuối cùng và nhẹ nhất — không bao giờ chặn việc chụp.
        // Viết theo góc nhìn NGƯỜI MẪU vì người cầm máy sẽ đọc to lên.
        if let hint = status.poseHint {
            var s = doiBenNeuLatGuong(hint, status.latGuong)
            if status.tuChup {
                s = s.removePrefix("Bảo mẫu ").firstLetterUppercased()
            }
            out = s
        } else {
            out = status.tuChup ? "Chỉnh dáng theo ảnh mẫu" : "Bảo mẫu chỉnh dáng theo ảnh mẫu"
        }

    case .SHARPNESS, .CROP, .EYES_OPEN:
        // Ba mục hậu kỳ không bao giờ tới được đây.
        out = ""
    }
    return out.trimmingCharacters(in: .whitespaces)
}

/// ĐỔI CHỮ "TRÁI" ↔ "PHẢI" trong câu nhắc dáng, khi hình đang xem bị lật gương.
///
/// ⚠️ Đổi ở CHỮ chứ không đổi ở phép đo, và đó là chủ ý: phép đo phải chạy trên
/// đúng khung hình sẽ được lưu ra. Chỗ duy nhất sai là CHỮ — bộ nhận diện đặt tên
/// theo giải phẫu của người TRONG ẢNH, mà người trong ảnh gương là bản lật của bạn.
nonisolated private let benTraiPhai = try! NSRegularExpression(pattern: "trái|phải")

nonisolated private func doiBenNeuLatGuong(_ text: String, _ latGuong: Bool) -> String {
    guard latGuong else { return text }
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    var out = text
    // Duyệt ngược để offset không bị lệch khi thay chuỗi cùng độ dài (trái↔phải
    // đều 4 ký tự tiếng Việt có dấu, nhưng vẫn an toàn nếu đổi khác độ dài).
    let matches = benTraiPhai.matches(in: text, range: range).reversed()
    for m in matches {
        let word = ns.substring(with: m.range)
        let swapped = word == "trái" ? "phải" : "trái"
        out = (out as NSString).replacingCharacters(in: m.range, with: swapped)
    }
    return out
}

nonisolated private extension String {
    func firstLetterUppercased() -> String {
        guard let f = first else { return self }
        return f.uppercased() + dropFirst()
    }

    func removePrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
