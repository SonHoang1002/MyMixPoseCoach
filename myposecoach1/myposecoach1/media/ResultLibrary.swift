import Foundation

/// THƯ VIỆN ẢNH ĐÃ LỌC — nơi chứa kết quả cuối, xem lại bất cứ lúc nào.
///
/// ## Vì sao tách khỏi `ShotStore`
///
/// `ShotStore` giữ **ảnh tạm của MỘT lần quay**, và có bốn lớp dọn rác để không
/// bao giờ tích tụ. Thư viện thì ngược lại: ảnh ở đây **cố ý giữ lại** cho tới khi
/// người dùng tự xoá.
///
/// Trộn hai thứ là hỏng theo cả hai chiều — hoặc dọn nhầm ảnh người ta muốn giữ,
/// hoặc để rác tạm nằm lại mãi.
///
/// ## ⚠️ Luật cứng: XOÁ NGUỒN GỐC sau khi lọc
///
/// Video thô 30 giây Full HD nặng 60-100 MB, một loạt ảnh chụp liên tục cũng vài
/// chục MB. Giữ lại là **rác nặng nhất của app**. Sau khi lọc xong và ghi ảnh kết
/// quả vào đây thì nguồn bị xoá ngay — xem `saveSession`.
nonisolated enum ResultLibrary {

    private static let TAG = "ResultLibrary"

    /// Thư mục ảnh kết quả: `Documents/ket-qua/`.
    private static let DIR = "ket-qua"

    /// Thư mục thư viện. Tự tạo nếu chưa có.
    static func dir() -> URL {
        let fm = FileManager.default
        let d = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(DIR, isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// MỘT LẦN CHỤP đã lọc xong: một thư mục con chứa các ảnh kết quả.
    ///
    /// Tên thư mục theo thời điểm nên xếp được theo thứ tự mà không cần đọc file.
    struct Album: Equatable {
        var dir: URL
        /// Ảnh mẫu đã dùng, chép vào để xem lại đối chiếu. `nil` = không còn.
        var templateThumb: URL?
        var photos: [URL]

        var createdAtMs: Int64 { ResultLibrary.lastModifiedMs(dir) }
        var count: Int { photos.count }
    }

    /// Mọi lần chụp đã lưu, mới nhất đứng đầu.
    static func albums() -> [Album] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(
            at: dir(),
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
        )) ?? []
        return items
            .filter { isDirectory($0) }
            .sorted { lastModifiedMs($0) > lastModifiedMs($1) }
            .map { d -> Album in
                let files = ((try? fm.contentsOfDirectory(
                    at: d,
                    includingPropertiesForKeys: [.isRegularFileKey]
                )) ?? []).filter { isFile($0) }
                return Album(
                    dir: d,
                    templateThumb: files.first(where: { $0.lastPathComponent == TEMPLATE_NAME }),
                    photos: files
                        .filter { $0.lastPathComponent != TEMPLATE_NAME }
                        .sorted { $0.lastPathComponent < $1.lastPathComponent }
                )
            }
            .filter { !$0.photos.isEmpty }
    }

    /// Chuyển kết quả một lần quay vào thư viện, rồi **XOÁ SẠCH nguồn**.
    ///
    /// @param sessionDir thư mục tạm của `ShotStore`
    /// @param templateFile ảnh mẫu đã dùng, chép vào album để sau còn đối chiếu
    /// @param sources video thô hoặc loạt ảnh gốc — **bị xoá sau khi chép xong**
    /// @return thư mục album mới, `nil` nếu không có ảnh nào để lưu
    static func saveSession(
        sessionDir: URL,
        templateFile: URL?,
        sources: [URL]
    ) -> URL? {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(
            at: sessionDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        )) ?? []
        let photos = files
            .filter { isFile($0) && IMAGE_EXT.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if photos.isEmpty {
            NSLog("%@", "\(TAG): Phiên không có ảnh nào, không lưu vào thư viện")
            return nil
        }

        let album = dir()
            .appendingPathComponent("buoi-\(Int64(Date().timeIntervalSince1970 * 1000))", isDirectory: true)
        try? fm.createDirectory(at: album, withIntermediateDirectories: true)
        do {
            for (i, f) in photos.enumerated() {
                let dich = album.appendingPathComponent(String(format: "anh-%02d.jpg", i + 1))
                try Data(contentsOf: f).write(to: dich)
            }
            if let templateFile {
                try Data(contentsOf: templateFile).write(to: album.appendingPathComponent(TEMPLATE_NAME))
            }
        } catch {
            NSLog("%@", "\(TAG): Chép vào thư viện không xong — \(error)")
            try? fm.removeItem(at: album)
            return nil
        }

        // ⚠️ XOÁ NGUỒN NGAY. Đây là luật cứng, không phải dọn dẹp cho gọn: một
        // đoạn video 30 giây Full HD nặng 60-100 MB. Chỉ cần quên vài lần là máy
        // người dùng đầy, mà họ không hiểu vì sao.
        for s in sources { try? fm.removeItem(at: s) }
        try? fm.removeItem(at: sessionDir)

        NSLog("%@", "\(TAG): Đã lưu \(photos.count) ảnh vào \(album.lastPathComponent), đã xoá nguồn")
        return album
    }

    /// Xoá hẳn một album. Không hỏi lại — bên gọi phải xác nhận trước.
    static func delete(_ album: Album) {
        try? FileManager.default.removeItem(at: album.dir)
    }

    private static func lastModifiedMs(_ url: URL) -> Int64 {
        let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return d.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
    }

    private static func isFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    private static let TEMPLATE_NAME = "_mau.jpg"
    private static let IMAGE_EXT: Set<String> = ["jpg", "jpeg", "png"]
}
