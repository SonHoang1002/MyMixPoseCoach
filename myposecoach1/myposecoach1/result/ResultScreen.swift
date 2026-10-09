import SwiftUI
import UIKit

/// MÀN KẾT QUẢ — dựng theo thiết kế Figma "V2 · 03 Ảnh đẹp nhất".
///
/// Bố cục: thanh tiêu đề có nút quay lại → dải ảnh ứng viên → ảnh đang chọn cỡ lớn
/// kèm nhãn "Khớp mẫu tốt nhất" → hai nút Lưu hết / Lưu ảnh này.
///
/// Khác thiết kế đúng hai chỗ, cố ý:
///  - **Bảng phân tích điểm** mở ra được. Thiết kế chỉ hiện ảnh, nhưng khi ảnh chọn
///    ra không giống mẫu thì người dùng không có cách nào biết vì sao — mà đó lại
///    là câu hỏi đầu tiên họ sẽ hỏi.
///  - **Cảnh báo khi không tấm nào đạt**. Thiếu nó thì app bày 5 tấm sai hoàn toàn
///    y hệt như khi kết quả tốt (luật số 7: không thất bại im lặng).
///
/// Port 1:1 từ `result/ResultScreen.kt`.
struct ResultScreen: View {

    @StateObject private var vm = ResultViewModel()

    private let templateFile: URL
    private let sessionDir: URL
    private let onDone: (_ continueShooting: Bool) -> Void

    /// - Parameter onDone: `true` = quay lại camera chụp tiếp, `false` = sang Thư viện.
    init(
        templateFile: URL,
        sessionDir: URL,
        onDone: @escaping (_ continueShooting: Bool) -> Void
    ) {
        self.templateFile = templateFile
        self.sessionDir = sessionDir
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            ResultHeader(onBack: { onDone(false) })

            Group {
                if vm.state.loading {
                    VStack(spacing: 0) {
                        Spacer()
                        ProgressView().tint(Ds.primary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if vm.state.isEmpty {
                    ResultEmptyState(onDone: { onDone(true) })
                } else {
                    ResultBody(state: vm.state, onAction: vm.onAction)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Ds.bg.ignoresSafeArea() }
        // Tương đương `LaunchedEffect(sessionDir)`: mỗi lần quay mới là một sessionDir
        // khác, khi đó `load` tự xoá trạng thái cũ và nạp lại.
        .task(id: sessionDir) {
            vm.load(
                sessionDir: sessionDir,
                templateFile: templateFile,
                // Ảnh giữ lại đi thẳng vào THƯ VIỆN — chỗ duy nhất chứa ảnh kết quả,
                // xem lại bất cứ lúc nào ở tab "Thư viện".
                keepDir: ResultLibrary.dir().appendingPathComponent(
                    "buoi-\(Int64(Date().timeIntervalSince1970 * 1000))",
                    isDirectory: true
                )
            )
        }
        // Xử lý xong (giữ hoặc bỏ) thì đóng màn. Đợi một nhịp để người dùng kịp đọc
        // dòng báo đã lưu ở đâu.
        .onChange(of: vm.state.finished) { _, finished in
            guard finished else { return }
            let daLuu = vm.state.savedPath != nil
            Task {
                try? await Task.sleep(nanoseconds: daLuu ? 1_600_000_000 : 250_000_000)
                onDone(vm.state.continueShooting)
            }
        }
    }
}

// MARK: - Thanh tiêu đề

private struct ResultHeader: View {
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Text("Kết quả")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Ds.text)

            HStack {
                Button(action: onBack) {
                    Text("‹")
                        .font(.system(size: 26))
                        .foregroundColor(Ds.text)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
    }
}

// MARK: - Thân màn

private struct ResultBody: View {
    let state: ResultUiState
    let onAction: (ResultAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !state.failedCriteria.isEmpty {
                        ResultFailureNotice(failed: state.failedCriteria)
                    }

                    ResultShotStrip(state: state, onAction: onAction)

                    // --- Ảnh đang chọn, cỡ lớn ---
                    ZStack(alignment: .topTrailing) {
                        Rectangle()
                            .fill(Color.black)
                            .aspectRatio(0.75, contentMode: .fit)
                            .overlay {
                                if let img = state.selected?.image {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                }
                            }

                        // Nhãn "khớp nhất" chỉ hiện khi thật sự có tấm đạt — gắn nhãn
                        // khen cho một tấm sai hoàn toàn thì còn tệ hơn không gắn gì.
                        if state.failedCriteria.isEmpty, let sel = state.selected {
                            Text("Khớp mẫu tốt nhất  \(sel.scoreText)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Ds.primary)
                                .clipShape(Capsule())
                                .padding(10)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Ds.rCard))

                    ResultScoreBreakdown(state: state)
                    Color.clear.frame(height: 4)
                }
                .padding(.horizontal, Ds.pageH)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let message = state.message {
                Text("⚠ \(message)")
                    .font(.system(size: 12))
                    .foregroundColor(Ds.dangerText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Ds.pageH)
            }
            if let savedPath = state.savedPath {
                Text("✓ Đã lưu: \(savedPath)")
                    .font(.system(size: 11))
                    .foregroundColor(Ds.success)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Ds.pageH)
            }

            // --- Hai nút hành động, ghim đáy ---
            HStack(spacing: 10) {
                // ⚠️ Nút này KHÔNG xoá. Người dùng vừa quay 30 giây — "đóng" phải hiểu
                // là "để đấy đã, tôi chụp tiếp", không phải "vứt đi". Muốn vứt thì vào
                // tab Thư viện xoá cả album, ở đó có hỏi lại.
                Button { onAction(.SaveAllAndContinue) } label: {
                    Text("Lưu hết & chụp tiếp")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Ds.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.plain)
                .disabled(state.finished)
                .background(Ds.surface)
                .clipShape(RoundedRectangle(cornerRadius: Ds.rCard))

                Button { onAction(.KeepSelected) } label: {
                    Text("Lưu ảnh này")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.plain)
                .disabled(state.finished || state.selected == nil)
                .background(state.finished ? Ds.textMuted : Ds.primary)
                .clipShape(RoundedRectangle(cornerRadius: Ds.rCard))
            }
            .padding(Ds.pageH)
        }
    }
}

// MARK: - Cảnh báo không tấm nào đạt

private struct ResultFailureNotice: View {
    let failed: [FailedCriterion]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Chưa tấm nào đạt " + failed.map(\.label).joined(separator: " · "))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Ds.dangerText)
            ForEach(Array(failed.enumerated()), id: \.offset) { _, f in
                Text("• \(f.advice)")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: 0x8A2B2F))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Ds.dangerSoft)
        .clipShape(RoundedRectangle(cornerRadius: Ds.rCard))
    }
}

// MARK: - Dải ảnh ứng viên

private struct ResultShotStrip: View {
    let state: ResultUiState
    let onAction: (ResultAction) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(state.shots.enumerated()), id: \.element.candidate.id) { index, shot in
                    let chosen = shot.candidate.id == state.selected?.candidate.id
                    ZStack(alignment: .bottomTrailing) {
                        Rectangle()
                            .fill(Ds.surfaceMuted)
                            .overlay {
                                if let img = shot.image {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                }
                            }
                            .clipped()

                        Text(shot.scoreText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: 0xCC000000))
                            .clipShape(Capsule())
                            .padding(4)
                    }
                    .frame(width: 84, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: Ds.rSmall))
                    .overlay {
                        if chosen {
                            RoundedRectangle(cornerRadius: Ds.rSmall)
                                .strokeBorder(Ds.primary, lineWidth: 2.5)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onAction(.Select(id: shot.candidate.id)) }
                    .accessibilityLabel("Ảnh thứ \(index + 1)")
                }
            }
        }
    }
}

// MARK: - Bảng phân tích

/// Thứ tự dòng bảng kê — lấy từ `Criterion` thay vì gõ cứng, đúng nguyên tắc của
/// `ShotStore.PART_KEYS`: thêm một tiêu chí mới mà quên sửa danh sách ở đây thì
/// bảng phân tích sẽ hiện sai mục mà vẫn trông hợp lệ.
private let RESULT_PART_ROWS: [(key: String, label: String)] =
    Criterion.allCases.map { (key: $0.key, label: $0.label) }

/// BẢNG PHÂN TÍCH — mất điểm ở mục nào. Mặc định thu gọn, bấm để mở.
///
/// Một con số tổng không nói được gì: "47" có thể là sai hướng hoàn toàn (mọi mục
/// khác đều tốt), cũng có thể là mọi mục đều lệch một chút. Hai chuyện đó khác hẳn
/// nhau, và cách sửa cũng khác hẳn.
private struct ResultScoreBreakdown: View {
    let state: ResultUiState

    @State private var expanded = false

    var body: some View {
        if let shot = state.selected {
            let parts = shot.candidate.parts

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(header(shot))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Ds.text)
                    Spacer()
                    Text(expanded ? "Thu gọn ▲" : "Chi tiết ▼")
                        .font(.system(size: 12))
                        .foregroundColor(Ds.primary)
                }

                if !shot.candidate.trustworthy {
                    Text("Điểm dựa trên ít mốc đo")
                        .font(.system(size: 11))
                        .foregroundColor(Ds.warning)
                }

                if expanded && !parts.isEmpty {
                    Color.clear.frame(height: 2)

                    ForEach(RESULT_PART_ROWS, id: \.key) { row in
                        // Vắng mặt = không áp dụng, bỏ qua.
                        if let v = parts[row.key] {
                            ResultPartRow(label: row.label, value: v)
                        }
                    }

                    // Mục vắng mặt = ảnh mẫu này không cần tới nó. Nói rõ ra, đừng để
                    // người dùng tự đoán vì sao thiếu dòng.
                    let missing = RESULT_PART_ROWS
                        .filter { parts[$0.key] == nil }
                        .map(\.label)
                    if !missing.isEmpty {
                        Text("Không áp dụng với ảnh mẫu này: " + missing.joined(separator: ", "))
                            .font(.system(size: 10))
                            .foregroundColor(Ds.textMuted)
                            .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Ds.surface)
            .clipShape(RoundedRectangle(cornerRadius: Ds.rCard))
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }
        }
    }

    private func header(_ shot: ResultShot) -> String {
        let giay = Double(shot.candidate.timeMs) / 1000.0
        let sec = String(
            format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), giay)
        return "Giây thứ \(sec)  ·  giống mẫu \(shot.scoreText)/100"
    }
}

/// Một dòng trong bảng phân tích: tên mục — thanh điểm — con số.
private struct ResultPartRow: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Ds.textMuted)
                .frame(width: 110, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Ds.surfaceMuted)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint)
                        .frame(width: barWidth(geo.size.width))
                }
            }
            .frame(height: 6)

            Text("\(Int(value * 100))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Ds.textMuted)
                .frame(width: 30, alignment: .leading)
                .padding(.leading, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func barWidth(_ total: CGFloat) -> CGFloat {
        let v = min(max(value, 0), 1)
        return max(0, total * CGFloat(v))
    }

    private var tint: Color {
        if value >= 0.75 { return Ds.success }
        if value >= 0.4 { return Ds.warning }
        return Ds.dangerText
    }
}

// MARK: - Trạng thái rỗng

private struct ResultEmptyState: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Không giữ được ảnh nào")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Ds.text)
            // Không "thất bại im lặng": nói rõ vì sao và làm gì tiếp.
            Text(
                "Trong cả lần quay, app không nhận ra người ở khung hình nào. " +
                    "Thử quay lại với mẫu đứng trọn trong khung và thấy rõ phần đầu."
            )
            .font(.system(size: 13))
            .foregroundColor(Ds.textMuted)
            .multilineTextAlignment(.center)
            .padding(.top, 8)

            Button(action: onDone) {
                Text("Quay lại")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .background(Ds.primary)
            .clipShape(RoundedRectangle(cornerRadius: Ds.rCard))
            .padding(.top, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Ds.pageH)
    }
}
