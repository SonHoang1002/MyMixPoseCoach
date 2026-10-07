import Foundation
import UIKit

/// KHO ẢNH TẠM của một lần quay.
///
/// Yêu cầu sản phẩm: *"video hay ảnh thừa được chụp liên tục đã lọc ra thì xoá
/// luôn tránh rác máy"*. Bốn lớp bảo vệ, cố ý chồng lên nhau vì mỗi lớp hụt ở một
/// tình huống khác nhau:
///
///  1. **Không bao giờ lưu quá `capacity` file** — [BestShotBuffer] đá khung yếu
///     ra ngay trong lúc quay, và mỗi lần đá là [delete] file luôn.
///  2. **Chọn xong thì xoá phần thừa** — người dùng giữ 1 tấm, 4 tấm kia biến mất.
///  3. **Thoát giữa chừng thì xoá cả phiên** — không để lại gì.
///  4. **[sweepOrphans] lúc mở app** — vớt nốt trường hợp app bị tắt đột ngột,
///     lớp 3 không kịp chạy. Không có lớp này thì mỗi lần app sập là để lại một
///     thư mục ảnh nằm lại vĩnh viễn.
///
/// ## Khác Android cần biết
///
/// Bản Android lấy gốc bằng `context.getExternalFilesDir(null)` — thư mục riêng
/// của app trên thẻ nhớ. iOS không có khái niệm đó, nên bản này dùng **Application
/// Support**: cũng riêng tư với app, cũng không hiện trong Files, và quan trọng
/// hơn là **không bị hệ điều hành xoá** như `Caches` — kho ảnh tạm mà bị xoá ngong
/// lúc đang mở thì màn kết quả sẽ hiện ô trống.
nonisolated final class ShotStore {

    let sessionDir: URL

    private init(sessionDir: URL) {
        self.sessionDir = sessionDir
        try? FileManager.default.createDirectory(
            at: sessionDir, withIntermediateDirectories: true)
    }

    func file(_ id: Int64) -> URL {
        sessionDir.appendingPathComponent("\(id).jpg")
    }

    // -----------------------------------------------------------------
    // Cắt tỉ lệ
    // -----------------------------------------------------------------

    /// CẮT ẢNH VỀ TỈ LỆ KHUNG người dùng chọn (phần GIỮA), trước khi ghi.
    /// Xem `TiLeKhung`.
    ///
    /// `nil` = giữ nguyên khung gốc.
    func cropToAspect(_ image: UIImage, _ targetAspect: Double?) -> UIImage {
        guard let targetAspect, targetAspect > 0 else { return image }
        let w = image.size.width
        let h = image.size.height
        if w <= 0 || h <= 0 { return image }
        let cur = Double(w) / Double(h)
        if abs(cur - targetAspect) / cur < 0.01 { return image }

        // Kích thước theo PIXEL, nhưng vẫn bắt đầu từ [image.size] — size của
        // UIImage đã tính theo chiều NHÌN THẤY (cờ EXIF đã áp), toạ độ cắt vì thế
        // cũng nằm trong hệ nhìn thấy. Cắt bằng toạ độ pixel thô của `cgImage` với
        // ảnh đang mang cờ EXIF = cắt nhầm chỗ.
        let scale = image.scale
        let pw = Int((w * scale).rounded())
        let ph = Int((h * scale).rounded())
        if pw <= 0 || ph <= 0 { return image }
        let nw: Int
        let nh: Int
        let ox: Int
        let oy: Int
        if targetAspect < cur {
            nw = min(max(Int(Double(ph) * targetAspect), 1), pw)
            nh = ph
            ox = (pw - nw) / 2
            oy = 0
        } else {
            nw = pw
            nh = min(max(Int(Double(pw) / targetAspect), 1), ph)
            ox = 0
            oy = (ph - nh) / 2
        }

        // Ảnh đã dựng đứng thì cắt thẳng khối điểm ảnh, không vẽ lại — rẻ hơn hẳn
        // và không đổi một pixel nào ngoài vùng cắt.
        if image.imageOrientation == .up, let cg = image.cgImage,
           cg.width == pw, cg.height == ph,
           let cropped = cg.cropping(to: CGRect(x: ox, y: oy, width: nw, height: nh)) {
            return UIImage(cgImage: cropped, scale: 1, orientation: .up)
        }

        // Còn lại: ảnh đang mang cờ EXIF (chụp liên tục, ảnh ra từ máy ảnh) hoặc
        // scale ≠ 1. Phải VẼ lại để áp đúng chiều nhìn — và lúc này pixels ghi ra
        // file đã dựng đứng, không cần cờ EXIF nữa.
        //
        // Renderer đặt `scale = 1` nên một đơn vị trong context = đúng một pixel:
        // [pw]/[ph] và [ox]/[oy] là pixel thì ghép thẳng được, không phải quy đổi
        // thêm lần nữa. `UIImage.draw(in:)` tự áp cờ EXIF, nên ảnh đang xoay cũng
        // ra đúng chiều người xem nhìn thấy.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: nw, height: nh), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(x: -ox, y: -oy, width: pw, height: ph))
        }
    }

    // -----------------------------------------------------------------
    // Ghi / xoá ảnh
    // -----------------------------------------------------------------

    /// Lưu một khung. Trả `false` nếu ghi hỏng — khi đó đừng đưa nó vào bộ giữ.
    func save(id: Int64, image: UIImage) -> Bool {
        guard let data = image.jpegData(compressionQuality: ShotStore.JPEG_QUALITY) else {
            NSLog("ShotStore: Không nén được khung \(id)")
            return false
        }
        do {
            try data.write(to: file(id), options: .atomic)
            return true
        } catch {
            NSLog("ShotStore: Không lưu được khung \(id) — \(error)")
            return false
        }
    }

    func delete(id: Int64) {
        try? FileManager.default.removeItem(at: file(id))
    }

    func delete(ids: [Int64]) {
        for id in ids { delete(id: id) }
    }

    /// Xoá sạch cả phiên, kể cả bảng kê.
    func deleteSession() {
        try? FileManager.default.removeItem(at: sessionDir)
    }

    // -----------------------------------------------------------------
    // Bảng kê — để màn kết quả đọc lại được mà không cần ViewModel còn sống
    // -----------------------------------------------------------------

    /// Ghi bảng kê khi quay xong.
    ///
    /// Cố ý ghi ra file thay vì truyền qua bộ nhớ: màn kết quả là một màn RIÊNG,
    /// và ViewModel của màn camera bị huỷ khi rời đi. Đọc lại từ đĩa thì màn kết
    /// quả không phụ thuộc gì vào màn trước — xoay máy hay app bị tạm dừng cũng
    /// không mất dữ liệu.
    func writeIndex(_ entries: [ShotCandidate]) {
        var s = "id,time_ms,score,trustworthy,\(ShotStore.PART_KEYS.joined(separator: ","))\n"
        for e in entries {
            s += "\(e.id),\(e.timeMs),\(num(e.score)),\(e.trustworthy)"
            // Mục KHÔNG đo được để trống, không ghi 0. Trống nghĩa là
            // "không biết"; 0 nghĩa là "biết, và sai hoàn toàn".
            for k in ShotStore.PART_KEYS {
                s += ","
                if let v = e.parts[k] { s += num(v) }
            }
            s += "\n"
        }
        do {
            try s.write(to: sessionDir.appendingPathComponent(ShotStore.INDEX_NAME),
                        atomically: true, encoding: .utf8)
        } catch {
            NSLog("ShotStore: Không ghi được bảng kê — \(error)")
        }
    }

    /// Đọc bảng kê. Trả danh sách rỗng nếu chưa có hoặc file hỏng.
    func readIndex() -> [ShotCandidate] {
        let url = sessionDir.appendingPathComponent(ShotStore.INDEX_NAME)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var out: [ShotCandidate] = []
        for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if i == 0 { continue } // bỏ dòng tiêu đề
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let c = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if c.count < 4 { continue }
            guard let id = Int64(c[0]) else { continue }
            // Bỏ qua dòng trỏ tới file đã không còn — tránh ô ảnh trống trên
            // màn kết quả mà không có lời giải thích nào.
            if !FileManager.default.fileExists(atPath: file(id).path) { continue }

            var parts: [String: Double] = [:]
            for (i2, key) in ShotStore.PART_KEYS.enumerated() {
                let at = 4 + i2
                if at >= c.count { break }
                let cell = c[at].trimmingCharacters(in: .whitespaces)
                if cell.isEmpty { continue }
                if let v = Double(cell) { parts[key] = v }
            }
            out.append(ShotCandidate(
                id: id,
                timeMs: Int64(c[1]) ?? 0,
                score: Double(c[2]) ?? 0.0,
                trustworthy: c[3].trimmingCharacters(in: .whitespaces) == "true",
                parts: parts,
            ))
        }
        return out
    }

    /// SỐ GHI RA FILE — **BẮT BUỘC** dùng `Locale` Mỹ.
    ///
    /// ⚠️ LỖI ĐÃ XẢY RA THẬT (06/09/2026, máy thật ngôn ngữ tiếng Việt):
    ///
    /// `"%.3f".format(x)` không chỉ định `Locale` thì lấy **ngôn ngữ của máy**. Máy
    /// cài tiếng Việt thì dấu thập phân là **DẤU PHẨY**: `0,899` chứ không phải `0.899`.
    ///
    /// Mà bảng kê này là CSV **ngăn cách bằng dấu phẩy**. Nên một giá trị biến thành
    /// HAI cột, mọi cột phía sau **trượt đi một ô**, và lúc đọc lại thì `0,899` ra
    /// thành `0` và `899`.
    ///
    /// Hậu quả người dùng thấy: thanh điểm nào cũng xanh đầy, con số hiện `899` thay
    /// vì `89`, và bảng phân tích "chưa tấm nào đạt mục X" chỉ sai bét.
    ///
    /// ⚠️ Không lộ trên máy ảo vì máy ảo mặc định tiếng Anh.
    ///
    /// Bản Swift dùng `String(format:locale:)` với `en_US_POSIX` — tương đương
    /// `Locale.US` bên Kotlin.
    private func num(_ v: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), v)
    }

    // -----------------------------------------------------------------
    // Thư mục
    // -----------------------------------------------------------------

    /// Thứ tự cột điểm từng mục trong bảng kê.
    ///
    /// Lấy thẳng từ [Criterion] thay vì gõ cứng: thêm một tiêu chí mới mà quên
    /// sửa danh sách này thì cột bị lệch, và bảng phân tích trên màn kết quả sẽ
    /// hiện điểm của mục này dưới tên mục khác — sai mà trông vẫn hợp lệ.
    static let PART_KEYS: [String] = Criterion.allCases.map { $0.key }

    private static let ROOT = "shots"
    private static let RECORDINGS = "recordings"

    /// Ảnh gốc của loạt chụp liên tục, trước khi chấm điểm.
    private static let BURST = "burst"

    private static let JPEG_QUALITY: CGFloat = 0.92
    private static let INDEX_NAME = "index.csv"

    /// Nơi chứa TẤT CẢ dữ liệu tạm của app — tương đương `getExternalFilesDir(null)`.
    private static func container() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static func folder(_ name: String) -> URL {
        let url = container().appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func rootDir() -> URL { folder(ROOT) }

    /// Nơi để video thô trong lúc chấm điểm. Xoá ngay sau khi cắt xong 5 ảnh.
    static func recordingsDir() -> URL { folder(RECORDINGS) }

    /// Nơi để ảnh gốc của loạt chụp liên tục, trong lúc chấm điểm.
    static func burstDir() -> URL { folder(BURST) }

    /// Dọn video thô bỏ lại.
    ///
    /// Đây là loại rác NẶNG NHẤT của app: một đoạn 30 giây ở Full HD khoảng
    /// 60-100 MB. Bình thường video bị xoá ngay sau khi cắt xong 5 ảnh, nhưng
    /// app bị giết giữa chừng thì nó nằm lại. Gọi lúc mở app.
    static func sweepRecordings() {
        let dir = recordingsDir()
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        for f in items {
            let mb = ((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) / 1024 / 1024
            NSLog("ShotStore: Dọn video bỏ lại: \(f.lastPathComponent) (\(mb) MB)")
            try? FileManager.default.removeItem(at: f)
        }
    }

    /// Dọn ảnh gốc của loạt chụp liên tục bỏ lại.
    ///
    /// Nhẹ hơn video thô nhiều (vài MB so với 60-100 MB) nhưng vẫn phải dọn:
    /// app bị giết giữa lúc chấm điểm thì cả loạt nằm lại vĩnh viễn. Cùng lý do
    /// với [sweepRecordings] — gọi lúc MỞ app, không phải lúc đóng.
    static func sweepBurst() {
        try? FileManager.default.removeItem(at: burstDir())
    }

    /// Mở một phiên mới. Tên thư mục theo thời điểm nên xếp được theo thứ tự.
    static func createSession() -> ShotStore {
        let ms = Int64(Date().timeIntervalSince1970 * 1000)
        return ShotStore(sessionDir: rootDir().appendingPathComponent("s\(ms)", isDirectory: true))
    }

    static func openSession(_ dir: URL) -> ShotStore { ShotStore(sessionDir: dir) }

    /// Dọn các phiên bỏ lại từ lần chạy trước.
    ///
    /// ⚠️ Gọi lúc MỞ APP, không phải lúc đóng. Lúc đóng thì app đã bị hệ điều
    /// hành giết rồi, code dọn dẹp không bao giờ chạy tới — đó chính là tình
    /// huống sinh ra rác.
    ///
    /// - Parameter keep: phiên đang dùng, không được xoá. `nil` = xoá hết.
    static func sweepOrphans(keep: URL? = nil) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: rootDir(), includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for dir in items {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let keep, dir.standardizedFileURL == keep.standardizedFileURL { continue }
            NSLog("ShotStore: Dọn phiên bỏ lại: \(dir.lastPathComponent)")
            try? FileManager.default.removeItem(at: dir)
        }
    }
}
