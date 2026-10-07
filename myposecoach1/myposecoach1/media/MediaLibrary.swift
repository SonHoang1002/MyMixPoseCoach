import Foundation

/// ĐỌC VÀ CÀI ĐẶT THƯ VIỆN ẢNH MẪU.
///
/// Đây là bộ khung **chạy thử**, đứng thay cho hai thứ của bản thật:
///   - `templates/` đứng thay **thư viện ảnh mẫu soạn sẵn** (sau này đóng gói trong app
///     hoặc tải từ server)
///   - `camera/` đứng thay **camera thời gian thực** (máy ảo không có người thật để soi)
///
/// Bản iOS dùng **thư mục riêng của app** (`Documents/templates/`) nên **không cần xin
/// quyền** đọc bộ nhớ — quyền đó ngày càng bị siết, và ta cũng không cần đọc file của
/// ứng dụng khác. Thư mục video/ảnh tạm (Android `camera/`) nằm ở `Caches/camera/`).
nonisolated enum MediaLibrary {

    private static let TEMPLATES_DIR = "templates"

    /// Thư mục ảnh mẫu soạn sẵn, ĐÓNG GÓI TRONG APP.
    private static let ASSET_TEMPLATES = "templates"

    /// Dấu vết "đã nạp ảnh mẫu soạn sẵn một lần rồi".
    ///
    /// ⚠️ Phải có, nếu không thì ảnh mẫu người dùng **xoá đi sẽ tự mọc lại** ở lần
    /// mở app kế tiếp — người dùng xoá xong thấy nó quay về sẽ nghĩ app hỏng.
    ///
    /// ⚠️ CÓ SỐ PHIÊN BẢN. Đổi số này là lần mở app kế tiếp sẽ **xoá bộ ảnh mẫu cũ
    /// do app cài sẵn** rồi chép bộ mới vào.
    ///
    /// Cần vì bộ ảnh mẫu sẽ còn thay nhiều lần. Không có số phiên bản thì ảnh cũ
    /// nằm lại mãi, lẫn với ảnh mới, và không có cách nào dọn ngoài việc bảo người
    /// dùng gỡ app.
    ///
    /// ⚠️ Chỉ xoá ảnh **do app cài sẵn** — ảnh người dùng tự chọn từ máy KHÔNG bị
    /// đụng tới. Danh sách ảnh cài sẵn ghi trong chính file đánh dấu.
    private static let SEED_MARKER = ".da-nap-anh-mau-v8"

    private static let IMAGE_EXT: Set<String> = ["jpg", "jpeg", "png", "webp", "jfif"]

    /// NHÓM ẢNH MẪU — ai cầm máy khi chụp ra bức ảnh đó.
    ///
    /// Quyết định luôn chế độ chụp cần dùng để tái tạo nó. Ảnh selfie gương chụp
    /// bằng camera SAU chĩa vào gương; ảnh selfie thường chụp bằng camera TRƯỚC —
    /// hai thứ khác nhau về chiều dịch máy, xem `ShootMode`.
    ///
    /// Nhận nhóm bằng TIỀN TỐ TÊN FILE, không cần file cấu hình riêng:
    ///
    ///     selfie-*  ->  SELFIE
    ///     mirror-*  ->  MIRROR
    ///     còn lại   ->  PHOTOGRAPHER
    ///
    /// Chọn cách này vì nó giữ đúng quy ước sẵn có "tên file là tên hiển thị", và
    /// thêm ảnh mới chỉ là thả file vào thư mục — không phải sửa code hay sửa thêm
    /// một file danh sách dễ quên đồng bộ.
    enum TemplateKind: CaseIterable {
        case PHOTOGRAPHER
        case SELFIE
        case MIRROR

        var label: String {
            switch self {
            case .PHOTOGRAPHER: return "Photographer"
            case .SELFIE: return "Selfie"
            case .MIRROR: return "Mirror"
            }
        }

        var prefix: String {
            switch self {
            case .PHOTOGRAPHER: return ""
            case .SELFIE: return "selfie-"
            case .MIRROR: return "mirror-"
            }
        }

        static func of(_ fileName: String) -> TemplateKind {
            let n = fileName.lowercased()
            return allCases.first(where: { !$0.prefix.isEmpty && n.hasPrefix($0.prefix) })
                ?? .PHOTOGRAPHER
        }
    }

    /// Một ảnh mẫu trong thư viện.
    struct Template: Equatable {
        var file: URL

        var kind: TemplateKind { TemplateKind.of(file.lastPathComponent) }

        /// Tên hiển thị: bỏ tiền tố nhóm, bỏ nhãn góc, bỏ đuôi, gạch ngang thành khoảng trắng.
        var displayName: String {
            let p = kind.prefix
            let p0 = p.hasSuffix("-") ? String(p.dropLast()) : p
            let tienTo = p0 + "-"
            let goc = file.deletingPathExtension().lastPathComponent
            let ten = goc.hasPrefix(tienTo) ? String(goc.dropFirst(tienTo.count)) : goc
            return MediaLibrary.boNhanGoc(ten)
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
        }
    }

    /// NHÃN GÓC MÁY trong tên file ảnh mẫu → độ nghiêng máy cần có, ĐỘ.
    ///
    /// Từ đầu tiên sau tiền tố nhóm:
    ///
    /// | Nhãn | Nghĩa | Góc |
    /// |---|---|---|
    /// | `tren` | máy trên cao, chúc xuống | −35° |
    /// | `ngang` | máy ngang tầm | 0° |
    /// | `duoi` | máy thấp, hất lên | +25° |
    ///
    /// Ví dụ: `selfie-tren-tai-nghe-nhin-nghieng.jpg`.
    ///
    /// ## Vì sao phải gán tay — cho MỌI ảnh mẫu, không riêng selfie (16/09/2026)
    ///
    /// Suy góc máy từ trục thân lẫn cả dáng đứng lẫn loại ống kính: ảnh studio chụp
    /// thẳng `ngang-nam-nen-trang-tay-tui` đọc ra +17°, và app bắt người chụp hạ máy
    /// chạm đất vẫn chưa đạt (FOOTGUNS 91).
    ///
    /// Với ảnh selfie **không có cách nào suy được góc máy từ ảnh**. Đã đo và loại
    /// lần lượt ba đường: tỉ lệ mặt/vai (tương quan −0,117), đường tai–mắt
    /// (+0,128), và góc ngửa/chúc của mặt từ ML Kit — cái cuối dao động −3° tới +2°
    /// trên đúng một ảnh chụp từ trên cao, vì người chụp selfie luôn nhìn vào máy.
    ///
    /// Tài liệu gốc đã tính trước ca này: *"template confidence thấp PHẢI được
    /// người gán tay"*. Thư viện ảnh mẫu vốn là thư viện chọn lọc, và đã dùng tên
    /// file để gán nhóm rồi.
    ///
    /// Ba mức thô chứ không ghi số độ: người gán nhìn ảnh bằng mắt, phân biệt được
    /// "từ trên / ngang / từ dưới" chứ không ước được 28° hay 35°. Ngưỡng đạt của
    /// mục này đủ rộng để ôm sai số đó.
    ///
    /// Có nhãn thì nhãn THẮNG phép suy từ ảnh — người gán nhìn thấy thứ máy không
    /// thấy. `nil` = không có nhãn.
    static func gocMayTheoNhan(_ nameWithoutExtension: String) -> Double? {
        GocMayNhan.cua(nameWithoutExtension)?.doNghieng
    }

    /// Ba mức góc máy gán tay. Xem `gocMayTheoNhan`.
    enum GocMayNhan: CaseIterable {
        case TREN
        case NGANG
        case DUOI

        var tu: String {
            switch self {
            case .TREN: return "tren"
            case .NGANG: return "ngang"
            case .DUOI: return "duoi"
            }
        }

        var nhan: String {
            switch self {
            case .TREN: return "Máy trên cao, chúc xuống"
            case .NGANG: return "Máy ngang tầm"
            case .DUOI: return "Máy thấp, hất lên"
            }
        }

        var doNghieng: Double {
            switch self {
            case .TREN: return -35.0
            case .NGANG: return 0.0
            case .DUOI: return 25.0
            }
        }

        static func cua(_ nameWithoutExtension: String) -> GocMayNhan? {
            let tu = tuDauSauTienTo(nameWithoutExtension)
            return allCases.first(where: { $0.tu == tu })
        }
    }

    /// NHÃN KIỂU CHỤP TỪ TRÊN CAO — từ THỨ HAI sau tiền tố nhóm, chỉ có nghĩa khi từ
    /// thứ nhất là `tren`: `tren-gan-…` · `tren-xa-…` (`tren-rong-…` cũ đọc thành gần). Xem `KieuChupTren`.
    static func kieuChupTrenTheoNhan(_ nameWithoutExtension: String) -> KieuChupTren? {
        if GocMayNhan.cua(nameWithoutExtension) != GocMayNhan.TREN { return nil }
        let n = nameWithoutExtension.lowercased()
        let kind = TemplateKind.of(n)
        let sau = kind.prefix.isEmpty ? n : String(n.dropFirst(kind.prefix.count))
        let sau2 = substringAfter(sau, "-", missing: "")
        return KieuChupTren.cuaTu(substringBefore(sau2, "-", missing: sau2))
    }

    /// Ảnh người dùng tự nhập — tên do `ganNhan` hoặc hàm chép ảnh đặt.
    static func laAnhNhap(_ file: URL) -> Bool {
        file.deletingPathExtension().lastPathComponent.contains(TIEN_TO_NHAP)
    }

    /// Gốc tên của ảnh tự nhập, dùng khi chép vào thư viện.
    static let TIEN_TO_NHAP = "toi-chon-"

    /// GÁN KIỂU CHỤP VÀ GÓC MÁY cho ảnh tự nhập, bằng cách ĐỔI TÊN FILE.
    ///
    /// ## Vì sao ảnh tự nhập bắt buộc phải có bước này
    ///
    /// Ảnh cài sẵn mang sẵn thông tin trong tên (`selfie-tren-…`). Ảnh tự nhập được
    /// chép vào dưới tên `toi-chon-<giờ>.jpg` — không có gì cả. Hậu quả trước đây:
    ///
    /// 1. **Sai camera.** Không có tiền tố `selfie-` nên app coi là ảnh người khác
    ///    chụp và mở CAMERA SAU, dù người dùng vừa nhập một tấm selfie.
    /// 2. **Selfie mất hai mục góc máy.** Không suy được góc máy từ ảnh selfie (đã
    ///    đo và loại ba cách, xem `gocMayTheoNhan`), và không có nhãn để thay.
    ///
    /// ## Vì sao lưu vào tên file
    ///
    /// Cùng một cơ chế với ảnh cài sẵn, nên từ đây trở đi ảnh tự nhập chạy **đúng
    /// một đường code** như ảnh cài sẵn — không có nhánh riêng nào để lệch nhau. Và
    /// không cần thêm kho lưu trữ nào: đổi tên xong là nhớ vĩnh viễn.
    ///
    /// @return file sau khi đổi tên; đổi tên thất bại thì trả lại file cũ.
    static func ganNhan(
        _ file: URL,
        kind: TemplateKind,
        goc: GocMayNhan?,
        /// Chỉ ghi khi `goc` là `GocMayNhan.TREN`.
        kieuTren: KieuChupTren? = nil
    ) -> URL {
        let goc0 = file.deletingPathExtension().lastPathComponent
        // Lột mọi tiền tố nhóm và nhãn góc cũ, chỉ giữ phần gốc "toi-chon-<giờ>".
        let idx = goc0.range(of: TIEN_TO_NHAP)?.lowerBound ?? goc0.startIndex
        let loiTen = String(goc0[idx...])
        var tenMoi = kind.prefix
        if let goc { tenMoi += goc.tu + "-" }
        if goc == GocMayNhan.TREN, let kieuTren { tenMoi += kieuTren.tu + "-" }
        tenMoi += loiTen
        tenMoi += "." + file.pathExtension
        if tenMoi == file.lastPathComponent { return file }
        let dich = file.deletingLastPathComponent().appendingPathComponent(tenMoi)
        do {
            try FileManager.default.moveItem(at: file, to: dich)
            return dich
        } catch {
            return file
        }
    }

    /// `substringBefore(dau)` của Kotlin: không có dấu phân cách thì trả `missing`.
    private static func substringBefore(_ s: String, _ dau: Character, missing: String) -> String {
        guard let i = s.firstIndex(of: dau) else { return missing }
        return String(s[..<i])
    }

    /// `substringAfter(dau)` của Kotlin: không có dấu phân cách thì trả `missing`.
    private static func substringAfter(_ s: String, _ dau: Character, missing: String) -> String {
        guard let i = s.firstIndex(of: dau) else { return missing }
        return String(s[s.index(after: i)...])
    }

    private static func tuDauSauTienTo(_ ten: String) -> String {
        let n = ten.lowercased()
        let kind = TemplateKind.of(n)
        let sau = kind.prefix.isEmpty ? n : String(n.dropFirst(kind.prefix.count))
        return substringBefore(sau, "-", missing: sau)
    }

    private static func boNhanGoc(_ tenSauTienTo: String) -> String {
        let tu = substringBefore(tenSauTienTo, "-", missing: tenSauTienTo).lowercased()
        if !(GocMayNhan.allCases.contains(where: { $0.tu == tu }) && tenSauTienTo.contains("-")) {
            return tenSauTienTo
        }
        let sau = substringAfter(tenSauTienTo, "-", missing: tenSauTienTo)
        // Sau nhãn "tren" có thể còn nhãn kiểu chụp — bỏ nốt.
        let tu2 = substringBefore(sau, "-", missing: sau).lowercased()
        if tu == GocMayNhan.TREN.tu && KieuChupTren.cuaTu(tu2) != nil && sau.contains("-") {
            return substringAfter(sau, "-", missing: sau)
        }
        return sau
    }

    static func templatesDir() -> URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(TEMPLATES_DIR, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// CHÉP THƯ VIỆN ẢNH MẪU SOẠN SẴN TỪ TRONG APP RA THƯ MỤC LÀM VIỆC.
    ///
    /// ⚠️ VÌ SAO CẦN: trước đây thư viện ảnh mẫu **chỉ tồn tại trên máy ảo**, do
    /// được đẩy vào bằng lệnh `adb push`. Cài app lên điện thoại thật thì thư mục
    /// đó rỗng từ đầu — người dùng mở app ra thấy trống trơn và tưởng ảnh mẫu
    /// "biến mất", trong khi thật ra chúng chưa bao giờ có mặt trên máy đó.
    ///
    /// Chép ra thư mục làm việc thay vì đọc thẳng từ trong app, vì mọi đường phía
    /// sau (cổng kiểm, phân tích, màn chụp) đều làm việc với `URL` thật trên đĩa.
    ///
    /// Gọi lúc mở app. Chạy đúng MỘT lần nhờ `SEED_MARKER`.
    static func seedBuiltInTemplates() {
        let dir = templatesDir()
        let marker = dir.appendingPathComponent(SEED_MARKER)
        let fm = FileManager.default
        if fm.fileExists(atPath: marker.path) { return }

        // Tương đương `runCatching` bên Kotlin: lỗi khi nạp ảnh mẫu KHÔNG làm chết app.
        do {
            // Dọn bộ CŨ trước. Danh sách ảnh do app cài sẵn được ghi trong chính
            // file đánh dấu của phiên bản trước, nên biết chính xác cái nào của
            // app và cái nào người dùng tự thêm.
            let cu = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for old in cu where old.lastPathComponent.hasPrefix(".da-nap-anh-mau") {
                let lines = (try? String(contentsOf: old, encoding: .utf8))?
                    .components(separatedBy: .newlines) ?? []
                for raw in lines {
                    let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty {
                        let f = dir.appendingPathComponent(line)
                        if fm.fileExists(atPath: f.path) { try? fm.removeItem(at: f) }
                    }
                }
                try? fm.removeItem(at: old)
            }

            let files = bundleTemplateFiles()
            for src in files {
                let data = try Data(contentsOf: src)
                try data.write(to: dir.appendingPathComponent(src.lastPathComponent))
            }
            // Ghi lại đúng những gì mình vừa chép, để lần sau dọn được sạch.
            let names = files.map { $0.lastPathComponent }
            try names.joined(separator: "\n").write(to: marker, atomically: true, encoding: .utf8)
        } catch {
            // Nuốt lỗi như `runCatching` bên Kotlin — lần mở app sau sẽ thử lại.
        }
    }

    /// Danh sách file ảnh mẫu soạn sẵn ĐÓNG GÓI TRONG APP.
    ///
    /// Android có `context.assets.list("templates")`; iOS không có tương đương. Thử
    /// hai đường, vì Xcode có thể giữ nguyên cấu trúc thư mục hoặc dàn phẳng tài
    /// nguyên ra khỏi bundle:
    ///  1. `<bundle>/templates/` — cấu trúc thư mục được giữ nguyên.
    ///  2. `<bundle>/` — tài nguyên bị dàn phẳng; lọc theo đuôi ảnh nên vẫn đúng.
    private static func bundleTemplateFiles() -> [URL] {
        let fm = FileManager.default
        guard let res = Bundle.main.resourceURL else { return [] }
        let sub = res.appendingPathComponent(ASSET_TEMPLATES, isDirectory: true)
        let dir = fm.fileExists(atPath: sub.path) ? sub : res
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.filter { IMAGE_EXT.contains($0.pathExtension.lowercased()) }
    }

    /// Danh sách ảnh mẫu, xếp theo tên cho ổn định thứ tự giữa các lần mở.
    static func templates() -> [Template] {
        let fm = FileManager.default
        let dir = templatesDir()
        let items = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey]
        )) ?? []
        return items
            .filter { url in
                let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                return isFile && IMAGE_EXT.contains(url.pathExtension.lowercased())
            }
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
            .map { Template(file: $0) }
    }
}
