import SwiftUI
import PhotosUI

/// MÀN HÌNH CHÍNH — chọn ảnh mẫu muốn chụp theo.
///
/// Port 1:1 từ `home/HomeScreen.kt` của Android: giữ nguyên thứ tự code, mọi label
/// tiếng Việt, và **CỔNG KIỂM ẢNH 3 MỨC** (§7.7) chạy TRƯỚC khi vào màn camera.
/// Ảnh không phân tích được thì KHÔNG BAO GIỜ vào được màn chụp — bản iOS cũ cho
/// mọi ảnh vào rồi im lặng không hướng dẫn gì, ngõ cụt không lối thoát.
///
/// Hai chỗ khác Android, cả hai đều do API nền tảng:
///  - Photo Picker của Android → `.photosPicker(isPresented:)` của PhotosUI. Cũng
///    KHÔNG cần xin quyền đọc thư viện: người dùng trao đúng tấm ảnh họ chọn.
///  - `LazyVerticalGrid` → `ScrollView` + `LazyVGrid`. Thanh tab nằm NGOÀI màn hình
///    này (ContentView xếp hai anh em dọc) nên lưới không phải chừa chỗ cho tab.
struct HomeScreen: View {
    let onPickTemplate: (URL) -> Void

    init(onPickTemplate: @escaping (URL) -> Void) {
        self.onPickTemplate = onPickTemplate
    }

    // --- Thư viện ảnh mẫu ---
    @State private var templates: [MediaLibrary.Template] = []

    /// Nhóm đang lọc. `null` = tất cả.
    ///
    /// Không cất vào ViewModel: đây là lựa chọn xem tạm của một lần mở màn hình,
    /// mất đi khi thoát cũng không sao.
    @State private var filter: MediaLibrary.TemplateKind? = nil

    /// Ảnh thu nhỏ của lưới, khoá theo tên file. Giải mã ở luồng nền.
    @State private var thumbs: [String: UIImage] = [:]

    // --- Trạng thái của cổng kiểm ---
    /// Ảnh đang được phân tích. `nil` = không có gì chạy.
    @State private var checking: URL? = nil
    @State private var verdict: (file: URL, kq: TemplateVerdict)? = nil
    @State private var importError: String? = nil
    @State private var profile: TemplateProfile? = nil

    /// Mô tả dáng và độ khó, suy từ chính khung xương của ảnh mẫu.
    ///
    /// ⚠️ Tính ở đây chứ không nhét vào `TemplateProfile`: hồ sơ nằm ở tầng đo đạc,
    /// còn đây là chuyện CÂU CHỮ cho người đọc. Trộn vào nhau sẽ kéo tầng đo phụ
    /// thuộc ngược lên tầng hướng dẫn.
    @State private var poseGuide: [String] = []
    @State private var difficulty: PoseDescriber.Difficulty? = nil

    // --- Import ảnh của người dùng ---
    @State private var importing = false

    /// Ảnh vừa chép vào, đang chờ gắn nhãn trong `NhapAnhSheet`.
    @State private var nhapMoi: URL? = nil

    /// File đang mở trong bảng gắn nhãn.
    ///
    /// Khác `nhapMoi`: giữ nguyên cả lúc bảng đang trượt xuống, để nội dung không
    /// biến mất giữa chừng (SwiftUI đọc lại `isPresented` ngay khi state đổi).
    @State private var sheetFile: URL? = nil

    /// Người dùng bấm "Chọn ảnh khác" → sau khi bảng đóng hẳn mới mở lại picker.
    @State private var moPickerSauKhiDong = false
    @State private var showPicker = false
    @State private var pickedItem: PhotosPickerItem? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 10)
            Text(PAGE_TITLE)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Ds.text)
            Text(PAGE_SUB)
                .font(.system(size: 12))
                .foregroundColor(Ds.textMuted)
                .padding(.top, 3)

            Color.clear.frame(height: 14)
            importCard
            Color.clear.frame(height: 14)

            // Chỉ hiện hàng lọc khi thư viện thật sự có nhiều hơn một nhóm — một
            // hàng chip mà bấm cái nào cũng ra y hệt thì chỉ tổ chiếm chỗ.
            if kindList.count > 1 {
                HomeFilterRow(kinds: kindList, selected: filter) { filter = $0 }
                Color.clear.frame(height: 12)
            }

            if shown.isEmpty {
                EmptyLibrary()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: Ds.gap),
                            GridItem(.flexible(), spacing: Ds.gap),
                        ],
                        spacing: Ds.gap
                    ) {
                        ForEach(shown, id: \.file) { t in
                            HomeTemplateTile(
                                name: t.displayName,
                                thumb: thumbs[t.file.lastPathComponent],
                                checking: checking == t.file,
                                onClick: {
                                    if checking == nil { runGate(t.file) }
                                }
                            )
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(.horizontal, Ds.pageH)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Ds.bg.ignoresSafeArea())
        .onAppear { reloadLibrary() }
        // Photo Picker: KHÔNG cần xin quyền đọc bộ nhớ. Người dùng chỉ trao đúng
        // tấm ảnh họ chọn, app không thấy gì khác.
        .photosPicker(isPresented: $showPicker, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            importing = true
            Task { @MainActor in
                let data = try? await item.loadTransferable(type: Data.self)
                // Chép + kiểm ảnh ở luồng nền: ảnh điện thoại vài MB, ghi đĩa và
                // giải mã trên main là khung hình đứng im giữa lúc bấm.
                let copied = await Task.detached(priority: .userInitiated) {
                    copyIntoLibrary(data: data)
                }.value
                importing = false
                // PHẢI xoá lựa chọn cũ: nếu giữ nguyên thì bấm đúng tấm ảnh lần hai
                // sẽ không có onChange nào nữa và app "đứng im" không hiểu vì sao.
                pickedItem = nil
                if let copied {
                    // CHƯA nạp lại thư viện: ảnh chưa gắn nhãn thì chưa phải ảnh mẫu.
                    // Xem `NhapAnhSheet`. Cổng kiểm vẫn chạy ngay trong bảng, không
                    // có đường tắt cho ảnh tự nhập.
                    sheetFile = copied
                    nhapMoi = copied
                } else {
                    importError = "Không đọc được ảnh vừa chọn. Thử ảnh khác."
                }
            }
        }
        .alert("Không dùng được ảnh này", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("Đóng") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .sheet(
            isPresented: Binding(
                get: { nhapMoi != nil },
                // Vuốt đóng bảng cũng = Huỷ: xoá file tạm, không để rác trong thư viện.
                set: { if !$0 { huyNhapAnh() } }
            ),
            onDismiss: {
                sheetFile = nil
                // "Chọn ảnh khác" → mở lại picker SAU khi bảng đã đóng hẳn. Nối hai
                // lần present bằng onDismiss: present hai sheet cùng lúc thì SwiftUI
                // bỏ mất một cái và người dùng không hiểu vì sao picker không mở.
                if moPickerSauKhiDong {
                    moPickerSauKhiDong = false
                    showPicker = true
                }
            }
        ) {
            if let f = sheetFile {
                NhapAnhSheet(
                    file: f,
                    onHuy: huyNhapAnh,
                    onChonAnhKhac: {
                        // Đúng thứ tự của Android: xoá file tạm, đóng bảng, MỞ LẠI
                        // picker để chọn tấm khác.
                        moPickerSauKhiDong = true
                        huyNhapAnh()
                    },
                    onLuu: { luu, kq in
                        nhapMoi = nil
                        reloadLibrary()
                        hienKetQua(file: luu, kq: kq)
                    }
                )
            }
        }
        .overlay {
            if let v = verdict {
                GateDialog(
                    verdict: v.kq,
                    profile: profile,
                    onDismiss: { verdict = nil },
                    poseGuide: poseGuide,
                    difficulty: difficulty,
                    onProceed: {
                        verdict = nil
                        onPickTemplate(v.file)
                    }
                )
            }
        }
    }

    // MARK: - Dữ liệu lưới

    /// Nhóm có thật trong thư viện, xếp theo thứ tự khai báo trong enum cho ổn định
    /// giữa các lần mở — đừng theo thứ tự file xuất hiện.
    private var kindList: [MediaLibrary.TemplateKind] {
        let co = Set(templates.map { $0.kind })
        return MediaLibrary.TemplateKind.allCases.filter { co.contains($0) }
    }

    /// Ảnh đang hiện ra theo bộ lọc.
    private var shown: [MediaLibrary.Template] {
        filter.map { k in templates.filter { $0.kind == k } } ?? templates
    }

    // MARK: - Cổng kiểm

    /// Hiện hộp thoại tiêu chí từ một kết quả phân tích đã có.
    private func hienKetQua(file: URL, kq: PhanTichAnhMau) {
        // Nhãn góc máy / kiểu chụp nằm trong TÊN FILE — đọc theo tên không đuôi.
        let ten = file.deletingPathExtension().lastPathComponent
        profile = kq.hoSo(
            gocMayNhan: MediaLibrary.gocMayTheoNhan(ten),
            kieuChupTren: MediaLibrary.kieuChupTrenTheoNhan(ten)
        )
        poseGuide = kq.poseGuide
        difficulty = kq.difficulty
        // Luôn hiện hộp thoại khi NHẬN, kể cả không có cảnh báo: người dùng cần
        // biết ảnh mẫu này sẽ được chấm theo tiêu chí nào TRƯỚC khi vào màn camera.
        verdict = (file, kq.verdict)
    }

    private func runGate(_ file: URL) {
        checking = file
        Task { @MainActor in
            // Phân tích MỘT LẦN rồi dùng cho cả cổng kiểm lẫn hồ sơ tiêu chí.
            //
            // ⚠️ PHẢI tách luồng nền: `phanTichAnhMau` giải mã ảnh và chạy Vision
            // — đặt lên main là màn hình đứng im 1-2 giây mỗi lần bấm.
            // Tương đương `withContext(Dispatchers.Default)` bên Android.
            let kq = await Task.detached(priority: .userInitiated) {
                phanTichAnhMau(file: file)
            }.value
            checking = nil
            hienKetQua(file: file, kq: kq)
        }
    }

    /// Nạp lại thư viện ảnh mẫu. Phải gọi lại được, không chỉ chạy một lần lúc mở
    /// màn hình — người dùng import ảnh mới thì lưới phải hiện ngay.
    private func reloadLibrary() {
        Task { @MainActor in
            let duo = await Task.detached(priority: .userInitiated, operation: docThumbnails).value
            templates = duo.0
            thumbs = duo.1
        }
    }

    /// Xoá ảnh tạm của bảng gắn nhãn (Huỷ / vuốt đóng).
    ///
    /// Đọc `nhapMoi` trong state chứ không nhận file làm tham số: sau khi "Lưu" đã
    /// `ganNhan` ĐỔI TÊN file rồi, mà còn xoá theo tên cũ là mất ảnh vừa lưu.
    private func huyNhapAnh() {
        if let f = nhapMoi {
            try? FileManager.default.removeItem(at: f)
        }
        nhapMoi = nil
    }

    // MARK: - Thẻ import

    private var importCard: some View {
        Group {
            if importing || checking != nil {
                // Tương đương `clickable(enabled = false)` bên Android: đang import
                // hoặc đang kiểm ảnh thì không cho chọn thêm, tránh hai luồng chạy
                // song song và người dùng không biết tấm nào đang được xử lý.
                ImportCard(busy: importing)
            } else {
                Button(action: { showPicker = true }) {
                    ImportCard(busy: importing)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Thẻ import ảnh mẫu

/// THẺ "Import ảnh mẫu của bạn" — khối xanh nổi bật ngay dưới tiêu đề.
///
/// Đặt TRÊN lưới ảnh có sẵn, không giấu xuống dưới: theo thiết kế thì tự đưa ảnh
/// vào là đường đi chính ngang hàng với thư viện soạn sẵn, không phải tính năng phụ.
private struct ImportCard: View {
    let busy: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Ds.rSmall)
                    .fill(Color(hex: 0x33FFFFFF))
                if busy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text("+")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(busy ? IMPORT_BUSY : IMPORT_TITLE)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text(IMPORT_SUB)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: 0xCCFFFFFF))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(">")
                .font(.system(size: 18))
                .foregroundColor(Color(hex: 0xCCFFFFFF))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(Ds.primary)
        .clipShape(RoundedRectangle(cornerRadius: Ds.rCard))
    }
}

// MARK: - Ô ảnh mẫu trong lưới

/// Ô ảnh mẫu trong lưới.
///
/// Tên ĐẶT LÊN ảnh với dải tối phía dưới, không nằm dưới ảnh như trước: ở ảnh cao
/// hơn thì người trong ảnh mẫu dễ nhìn hơn hẳn.
private struct HomeTemplateTile: View {
    let name: String
    let thumb: UIImage?
    let checking: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            ZStack {
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Chưa có thumbnail (đang tải, hoặc file hỏng bị bỏ qua) thì hiện
                    // ô nền + vòng xoay, KHÔNG để chỗ trống đen.
                    Ds.surfaceMuted
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Ds.textMuted)
                }

                VStack {
                    Spacer()
                    HStack {
                        Text(name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(hex: 0x99000000))
                }

                // Phân tích ảnh mất 1-2 giây; không báo thì người dùng tưởng app treo.
                if checking {
                    ZStack {
                        Color(hex: 0xAA000000)
                        VStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                            Text(CHECKING_LABEL)
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(0.72, contentMode: .fit)
            .background(Ds.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: Ds.rTile))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hàng lọc theo nhóm

/// HÀNG LỌC THEO NHÓM.
///
/// Nhãn để TIẾNG ANH theo yêu cầu, và cũng hợp lý hơn tiếng Việt ở đây: ba nhóm đều
/// là từ ngắn quen thuộc (`Photographer`, `Selfie`, `Mirror`), dịch ra sẽ dài và rối
/// chip.
///
/// Nhóm nào thư viện không có thì KHÔNG hiện chip — chip bấm vào ra danh sách rỗng
/// là ngõ cụt vô nghĩa.
private struct HomeFilterRow: View {
    let kinds: [MediaLibrary.TemplateKind]
    let selected: MediaLibrary.TemplateKind?
    let onSelect: (MediaLibrary.TemplateKind?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HomeFilterChip(title: "All", selected: selected == nil) {
                    onSelect(nil)
                }
                ForEach(kinds, id: \.self) { k in
                    HomeFilterChip(title: k.label, selected: selected == k) {
                        // Bấm lại chip đang chọn thì bỏ lọc.
                        onSelect(selected == k ? nil : k)
                    }
                }
            }
        }
    }
}

/// Một viên lọc. Trạng thái chọn nhìn thấy được ngay: chữ và nền đều đổi màu.
private struct HomeFilterChip: View {
    let title: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(selected ? Ds.primary : Ds.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? Ds.primary.opacity(0.14) : Ds.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thư viện rỗng

private struct EmptyLibrary: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Chưa có ảnh mẫu nào")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Ds.text)
            Text("Bấm \"Chọn ảnh từ máy\" ở trên để thêm ảnh mẫu đầu tiên.")
                .font(.system(size: 12))
                .foregroundColor(Ds.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Nạp thư viện ở luồng nền

/// Nạp danh sách ảnh mẫu và ảnh thu nhỏ của lưới — CHỈ chạy ở luồng nền.
///
/// Ảnh thu nhỏ tải cỡ cạnh ngắn 320 cho nhẹ: lưới không cần ảnh độ phân giải đầy
/// đủ, tải nguyên cỡ dễ tràn bộ nhớ khi có nhiều ảnh.
///
/// - Returns: (danh sách, tên file → ảnh thu nhỏ).
nonisolated private func docThumbnails() -> ([MediaLibrary.Template], [String: UIImage]) {
    let list = MediaLibrary.templates()
    var map: [String: UIImage] = [:]
    for t in list {
        // File hỏng hoặc định dạng lạ thì giải mã trả về nil. BỎ QUA nó, đừng để
        // nguyên — trước đây chỗ này gọi thẳng `.asImageBitmap()` trên kết quả có
        // thể null, một file ảnh hỏng là sập cả màn hình.
        guard let img = UprightBitmap.decode(file: t.file, shortSide: 320) else {
            continue
        }
        map[t.file.lastPathComponent] = img
    }
    return (list, map)
}

// MARK: - Chép ảnh người dùng chọn

/// Chép ảnh người dùng chọn vào thư viện ảnh mẫu của app.
///
/// Vì sao phải CHÉP chứ không giữ đường dẫn gốc: photo picker chỉ đưa tạm cho app
/// một khối dữ liệu, không có đường dẫn ổn định. Giữ nguyên thì ảnh mẫu dùng được
/// hôm nay, mở lại app là hỏng — mà hỏng im lặng, không báo gì.
///
/// Chép vào `templates/` để ảnh nằm luôn trong lưới, dùng lại được những lần sau,
/// và đi qua đúng đường của ảnh soạn sẵn — không có nhánh riêng cho ảnh import.
///
/// Chạy ở luồng nền (gọi từ `Task.detached`).
///
/// - Returns: file đã chép, hoặc `nil` nếu không đọc được ảnh.
nonisolated private func copyIntoLibrary(data: Data?) -> URL? {
    guard let data else { return nil }
    do {
        let dir = MediaLibrary.templatesDir()
        // Tên tự đặt, không lấy tên gốc: tên file từ máy người dùng có thể có dấu
        // tiếng Việt, khoảng trắng, hoặc trùng tên ảnh đã có.
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let dest = dir.appendingPathComponent("\(MediaLibrary.TIEN_TO_NHAP)\(stamp).jpg")
        try data.write(to: dest)

        // Kiểm ảnh có giải mã được không NGAY tại đây. Chép một file rác rồi để lưới
        // tự vấp về sau thì lỗi hiện ra ở chỗ chẳng liên quan gì tới thao tác vừa rồi.
        if UprightBitmap.decode(file: dest, shortSide: 64) == nil {
            try? FileManager.default.removeItem(at: dest)
            return nil
        }
        return dest
    } catch {
        NSLog("HomeScreen: Không chép được ảnh vừa chọn — \(error)")
        return nil
    }
}

/* ---------------- Chuỗi hiển thị, gom một chỗ ---------------- */

private let PAGE_TITLE = "Chọn kiểu ảnh"
private let PAGE_SUB = "App sẽ chỉ người cầm máy chụp theo"
private let IMPORT_TITLE = "Import ảnh mẫu của bạn"
private let IMPORT_SUB = "App tự phân tích góc chụp"
private let IMPORT_BUSY = "Đang kiểm ảnh vừa chọn…"
private let CHECKING_LABEL = "Đang kiểm ảnh…"
