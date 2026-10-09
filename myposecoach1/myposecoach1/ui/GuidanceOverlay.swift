import SwiftUI

// PHẦN GIAO DIỆN HƯỚNG DẪN DÙNG CHUNG cho màn chụp — port 1:1 từ
// `ui/GuidanceOverlay.kt` của Android.
//
// Các hàm nhận THAM SỐ RỜI, không nhận cả `CaptureUiState`: phần hướng dẫn phải
// dùng lại được ở bất kỳ màn nào (màn chụp thật, màn giả lập video).

// MARK: - Danh sách điều kiện

/// DANH SÁCH ĐIỀU KIỆN CÓ DẤU TÍCH — bám trạng thái thật của từng cổng.
///
/// ⚠️ Bốn trạng thái, bốn ký hiệu khác nhau. Chỗ dễ làm sai nhất là gộp
/// `UNMEASURED` vào chung với "chưa đạt": **không đo được KHÁC với sai**
/// (luật số 4 của dự án). Khung hình che mất hông thì mục xa/gần không đo được —
/// hiện dấu X ở đó là nói dối người dùng rằng họ đang đứng sai chỗ.
struct CriteriaChecklist: View {
    let criteria: [CriterionStatus]

    var body: some View {
        if !criteria.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                // GỘP theo nhãn: `SCALE` và `PERSPECTIVE` là hai phép đo nhưng với
                // người dùng chỉ là MỘT câu hỏi — "tôi đứng đủ xa chưa?".
                ForEach(Array(groupRows(criteria).enumerated()), id: \.offset) { _, row in
                    let label = row.0
                    let item = row.1
                    let mark = markOf(item)
                    let tint = tintOf(item)
                    HStack(spacing: 6) {
                        Text(mark)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(tint)
                        Text(rowText(label: label, item: item))
                            .font(.system(size: 11))
                            .foregroundColor(
                                (item.state == .PASSING && !item.pending) ? Ds.success
                                    : Color(hex: 0xE6FFFFFF)
                            )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Ds.overlayScrim)
            .clipShape(RoundedRectangle(cornerRadius: Ds.rSmall))
        }
    }

    private func markOf(_ item: CriterionStatus) -> String {
        if item.skipped { return "~" }
        if item.pending { return "○" }
        switch item.state {
        case .PASSING: return "✓"
        case .FAILING: return "!"
        case .GREY: return "◐"
        case .UNMEASURED: return "–"
        }
    }

    private func tintOf(_ item: CriterionStatus) -> Color {
        if item.skipped { return Ds.warning }
        if item.pending { return Color(hex: 0x80FFFFFF) }
        switch item.state {
        case .PASSING: return Ds.success
        case .FAILING: return Ds.dangerText
        case .GREY: return Ds.warning
        case .UNMEASURED: return Color(hex: 0x80FFFFFF)
        }
    }

    private func rowText(label: String, item: CriterionStatus) -> String {
        if item.skipped { return "\(label) · bỏ qua" }
        if item.pending { return "\(label) · chờ" }
        return label
    }
}

// MARK: - Thanh tiến độ

/// THANH TIẾN ĐỘ — "đã đạt 4/6".
///
/// Đếm theo **dòng đã gộp**, không đếm theo tiêu chí thô — người dùng nhìn thấy
/// 6 dòng thì mẫu số phải là 6, không phải 7.
struct CriteriaProgress: View {
    let criteria: [CriterionStatus]

    /// Độ giống ảnh mẫu, 0..100. `nil` = hiện "Đã đạt x/y".
    var matchPercent: Int? = nil

    var body: some View {
        let rows = groupRows(criteria)
        if !rows.isEmpty {
            let done = rows.filter {
                !$0.1.pending && ($0.1.state == .PASSING || $0.1.skipped)
            }.count
            let total = rows.count
            let ratio = matchPercent.map { CGFloat($0) / 100.0 }
                ?? CGFloat(done) / CGFloat(total)

            VStack(alignment: .leading, spacing: 4) {
                Text(header(done: done, total: total))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(headerTint(done: done, total: total))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x33FFFFFF))
                        Capsule()
                            .fill(barTint(done: done, total: total))
                            .frame(width: max(4, geo.size.width * ratio))
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private func header(done: Int, total: Int) -> String {
        if let p = matchPercent {
            return "Giống mẫu \(p)%  ·  \(done)/\(total) điều kiện"
        }
        return "Đã đạt \(done)/\(total) điều kiện"
    }

    private func headerTint(done: Int, total: Int) -> Color {
        if let p = matchPercent, p >= 85 { return Ds.success }
        if done == total { return Ds.success }
        return Color(hex: 0xE6FFFFFF)
    }

    private func barTint(done: Int, total: Int) -> Color {
        let best = matchPercent.map { $0 >= 85 } ?? false
        return (best || done == total) ? Ds.success : Ds.warning
    }
}

/// Gộp các mục cùng nhãn thành MỘT dòng.
///
/// Mục đang hoạt động được hiện trước mục đã tích. Khi mục sau còn chờ
/// (ví dụ zoom sau khoảng cách), dòng gộp phải hiện "chờ" thay vì xanh sớm.
func groupRows(_ criteria: [CriterionStatus]) -> [(String, CriterionStatus)] {
    func rank(_ s: GateState) -> Int {
        switch s {
        case .FAILING: return 0
        case .GREY: return 1
        case .PASSING: return 2
        case .UNMEASURED: return 3
        }
    }
    var order: [String] = []
    var buckets: [String: [CriterionStatus]] = [:]
    for s in criteria {
        let label = s.criterion.displayLabel
        if buckets[label] == nil {
            buckets[label] = []
            order.append(label)
        }
        buckets[label]!.append(s)
    }
    return order.compactMap { label in
        guard let items = buckets[label] else { return nil }
        let pick = items.min { a, b in
            func score(_ s: CriterionStatus) -> Int {
                if s.pending || s.skipped { return 3 }
                return s.state == .PASSING ? 4 : rank(s.state)
            }
            return score(a) < score(b)
        }
        return pick.map { (label, $0) }
    }
}

// MARK: - Viên câu chỉ dẫn

enum CueTone { case OK, WARN, ALERT, NEUTRAL }

/// VIÊN CÂU CHỈ DẪN — mỗi lúc đúng MỘT câu.
///
/// Thứ tự xét trong hàm này **chính là thứ tự ưu tiên của sản phẩm**:
/// 1. Cầm máy sai (xoay ngang, đang zoom) — vì nó làm mọi phép đo phía sau mất nghĩa
/// 2. Chưa thấy mẫu — chưa có gì để đo
/// 3. Câu nhắc từ engine — đã chọn sẵn mục ưu tiên cao nhất
/// 4. Đủ điều kiện
struct CuePill: View {
    let prepWarning: String?
    let personDetected: Bool

    /// Câu nhắc hiện tại từ engine.
    var cue: String? = nil
    var readyToCapture: Bool = false
    var hasCriteria: Bool = false

    /// Câu đang hiện là câu để ĐỌC TO CHO MẪU NGHE. Chỉ đổi biểu tượng.
    var cueForModel: Bool = false

    /// Đã đủ giống ảnh mẫu để chuyển sang giục tạo dáng.
    var readyToPose: Bool = false

    /// Giây còn lại của đồng hồ tự động. `nil` = không đếm.
    var countdown: Int? = nil

    var onTapWarning: (() -> Void)? = nil

    private var resolved: (icon: String, text: String, tone: CueTone) {
        if let w = prepWarning { return ("⟳", w, .ALERT) }
        if !personDetected { return ("○", "Đưa máy về phía mẫu", .NEUTRAL) }
        // Đang đếm ngược: KHÔNG nhắc gì khác nữa, người ta đang tạo dáng.
        if let c = countdown { return ("●", "Giữ nguyên — \(c)", .OK) }
        if let cue { return (cueForModel ? "🗣" : "→", cue, .WARN) }
        if readyToCapture { return ("✓", "Đủ điều kiện rồi — bấm quay", .OK) }
        if readyToPose { return ("✓", "Góc máy đã ổn — chỉnh dáng rồi bấm quay", .OK) }
        if !hasCriteria { return ("○", "Đang đo…", .NEUTRAL) }
        // Không còn câu nhắc nào mà cũng chưa đủ: đang ở vùng đệm giữa hai ngưỡng.
        return ("◐", "Gần đúng — giữ máy ổn định một chút", .NEUTRAL)
    }

    var body: some View {
        let r = resolved
        HStack(spacing: 8) {
            Text(r.icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(tint(r.tone))
            Text(r.text)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Ds.text)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: 0xF2FFFFFF))
        .clipShape(Capsule())
        .onTapGesture {
            if prepWarning != nil { onTapWarning?() }
        }
    }

    private func tint(_ tone: CueTone) -> Color {
        switch tone {
        case .OK: return Ds.success
        case .WARN: return Ds.warning
        case .ALERT: return Ds.dangerText
        case .NEUTRAL: return Ds.textMuted
        }
    }
}

// MARK: - Thẻ ảnh mẫu

/// Thẻ ảnh mẫu nhỏ ở góc trên phải, có nhãn "MẪU".
struct TemplateCard: View {
    let thumb: UIImage?

    var body: some View {
        if let thumb {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 88, height: 132)
                    .clipped()
                    .background(Color.black)
                Text("MẪU")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: 0xCC000000))
                    .clipShape(Capsule())
                    .padding(5)
            }
            .frame(width: 88, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: Ds.rSmall))
        }
    }
}
