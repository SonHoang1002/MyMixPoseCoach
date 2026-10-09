import Combine
import Foundation
import UIKit

/// VIEWMODEL MÀN KẾT QUẢ — đúng ba khái niệm MVI như bản Android:
/// `ResultUiState` + `ResultAction` + lớp này chỉ có một hàm public [onAction].
///
/// Port 1:1 từ `result/ResultViewModel.kt`, khác hai chỗ bắt buộc:
///  - `StateFlow` → `@Published` (quy ước Observation của bản iOS),
///  - `viewModelScope.launch + withContext(Dispatchers.IO)` → `Task.detached`,
///    việc nặng (đọc bảng kê, giải mã ảnh) vẫn phải chạy NGOÀI main thread.
@MainActor
final class ResultViewModel: ObservableObject {

    @Published var state = ResultUiState()

    private var store: ShotStore? = nil

    /// Nơi ảnh được giữ lại khi bấm "Lưu ảnh này" — tính từ [load], đúng như bản
    /// Android: `ResultLibrary.dir()/buoi-<thời điểm mở màn>`.
    private var keepDir: URL? = nil

    /// Ảnh mẫu của lần quay này — `SaveAllAndContinue` cần để chép vào album
    /// (xem `ResultLibrary.saveSession`).
    private var templateFile: URL? = nil

    /// Thư mục phiên đã nạp. Dùng để phân biệt "ghép lại giao diện" (không nạp lại)
    /// với "một lần quay MỚI" (phải xoá sạch trạng thái cũ).
    private var loadedDir: String? = nil

    /// Nạp kết quả từ ĐĨA, không nhận từ màn trước.
    ///
    /// Cố ý như vậy: màn camera và màn này là hai màn riêng, ViewModel của màn
    /// trước đã bị huỷ khi rời đi. Đọc lại từ đĩa thì màn này tự đứng được.
    func load(sessionDir: URL, templateFile: URL, keepDir: URL) {
        // Cùng thư mục thì thôi — chỉ là giao diện dựng lại, không phải lần quay mới.
        if loadedDir == sessionDir.path { return }
        loadedDir = sessionDir.path

        // ⚠️ Thư mục KHÁC nghĩa là lần quay MỚI → phải xoá sạch trạng thái cũ.
        // Không xoá thì `finished = true` của lần trước còn sót lại, và màn hình
        // tự đóng ngay khi vừa mở — người dùng bị đá về trang chủ mà không hiểu vì sao.
        state = ResultUiState()

        let s = ShotStore.openSession(sessionDir)
        store = s
        self.keepDir = keepDir
        self.templateFile = templateFile

        Task {
            let tpl = templateFile
            // Ảnh điện thoại là hàng chục triệu điểm ảnh; nạp 5 tấm cùng lúc ở
            // kích thước gốc là chắc chắn hết bộ nhớ. Cỡ 720 (ảnh mẫu) và 1280
            // (khung) đúng như `decodeSampled` bên Android, và đều qua
            // `UprightBitmap` — KHÔNG đọc thẳng `UIImage(contentsOfFile:)`.
            let loaded = await Task.detached(priority: .userInitiated) {
                () -> (UIImage?, [(ShotCandidate, UIImage?)]) in
                let thumb = UprightBitmap.decode(file: tpl, shortSide: 720)
                let shots = s.readIndex().map { c in
                    (c, UprightBitmap.decode(file: s.file(c.id), shortSide: 1280))
                }
                return (thumb, shots)
            }.value

            var next = state
            next.loading = false
            next.templateName = tpl.deletingPathExtension().lastPathComponent
            next.templateThumb = loaded.0
            next.shots = loaded.1.map { ResultShot(candidate: $0.0, image: $0.1) }
            next.selectedId = next.shots.first?.candidate.id
            state = next
        }
    }

    /// Một hàm public duy nhất — mọi thao tác của người dùng đi qua đây.
    func onAction(_ action: ResultAction) {
        switch action {
        case .Select(let id):
            state.selectedId = id
        case .KeepSelected:
            keepSelected()
        case .SaveAllAndContinue:
            saveAllAndContinue()
        }
    }

    /// Giữ tấm đang chọn, xoá sạch phần còn lại.
    ///
    /// Chép ảnh RA NGOÀI thư mục phiên trước, rồi mới xoá cả phiên. Làm ngược lại
    /// — xoá 4 tấm kia trước rồi mới chép — thì nếu chép hỏng, người dùng mất
    /// trắng cả lần quay.
    ///
    /// ⚠️ Vì sao KHÔNG dùng `ResultLibrary.saveSession` ở đây: hàm đó lưu **CẢ**
    /// thư mục phiên (và tự đặt tên `anh-01.jpg…`) — đúng cho "Lưu hết", sai cho
    /// hành động này là chỉ giữ MỘT tấm. Bản Android cũng tự chép một file
    /// `<tên ảnh mẫu>-<id>.jpg` vào thư mục album, nên làm y chang:
    /// `ResultLibrary.albums()` vẫn liệt kê được (nó chỉ trừ file `_mau.jpg`).
    private func keepSelected() {
        guard let s = store, let dir = keepDir, let shot = state.selected else { return }
        let src = s.file(shot.candidate.id)
        let dest = dir.appendingPathComponent("\(state.templateName)-\(shot.candidate.id).jpg")

        Task {
            let saved = await Task.detached(priority: .userInitiated) { () -> Bool in
                do {
                    try FileManager.default.createDirectory(
                        at: dir, withIntermediateDirectories: true)
                    // Ghi đè được nếu người dùng bấm hai lần — `copyItem` thì lần
                    // thứ hai lỗi và hiện nhầm thông báo "không lưu được".
                    try Data(contentsOf: src).write(to: dest)
                    return true
                } catch {
                    NSLog("%@", "ResultViewModel: Không lưu được ảnh — \(error)")
                    return false
                }
            }.value

            guard saved else {
                state.message = "Không lưu được ảnh. Chưa xoá gì cả, thử lại được."
                return
            }

            // Chép xong MỚI xoá phiên — thứ tự này là luật cứng, ngược lại là mất
            // ảnh khi chép hỏng giữa chừng.
            await Task.detached(priority: .userInitiated) { s.deleteSession() }.value

            var next = state
            next.savedPath = dest.path
            next.finished = true
            next.message = nil
            state = next
        }
    }

    /// Lưu TẤT CẢ ảnh đã lọc vào thư viện rồi báo xong, để màn hình quay lại camera.
    ///
    /// ⚠️ Khác hẳn hành động cũ ở chỗ **không bỏ tấm nào**. Người dùng vừa quay 30
    /// giây; "đóng" ở đây nghĩa là *"cứ để đấy, tôi chụp tiếp"*.
    ///
    /// Dùng `ResultLibrary.saveSession` — nó tự chép cả ảnh mẫu `_mau.jpg` vào album
    /// rồi xoá thư mục phiên, đúng luật "chỉ xoá khi đã chép xong". ⚠️ Khác Android
    /// một chỗ: bản Android chỉ chép ảnh (`anh-01.jpg…`) và KHÔNG chép ảnh mẫu vào
    /// album; bản này chép thêm `_mau.jpg` để sau mở thư viện ra còn đối chiếu.
    private func saveAllAndContinue() {
        guard let s = store, let tpl = templateFile else { return }
        let sessionDir = s.sessionDir

        Task {
            let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                ResultLibrary.saveSession(
                    sessionDir: sessionDir,
                    templateFile: tpl,
                    // Nguồn thô (video, ảnh chụp gốc) đã bị xoá từ lúc chốt phiên,
                    // ở đây không còn gì để dọn.
                    sources: []
                ) != nil
            }.value

            var next = state
            if ok {
                next.finished = true
                next.continueShooting = true
                next.message = nil
            } else {
                // Không thất bại im lặng (luật số 7): nói rõ và CHƯA đóng màn.
                next.message = "Không lưu được ảnh nào. Chưa xoá gì cả."
            }
            state = next
        }
    }
}
