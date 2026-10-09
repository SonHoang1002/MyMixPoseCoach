import Foundation
import UIKit

/// Trạng thái màn xem lại — bước cuối của chuỗi lõi:
///
///     ảnh mẫu → hướng dẫn → quay → **chọn 5 ảnh khớp nhất** → giữ 1
///
/// Port 1:1 từ `result/ResultUiState.kt` — gồm luôn `ResultShot`,
/// `FailedCriterion` và `ResultAction`, đúng như bản Android gộp chung một file.
struct ResultUiState {

    var loading: Bool = true
    var templateName: String = ""

    /// Ảnh mẫu đã nạp sẵn (giải mã cỡ `shortSide = 720`, như `decodeSampled`
    /// bên Android) — bày cạnh ảnh kết quả để so.
    var templateThumb: UIImage? = nil

    /// Tối đa 5 khung, tốt nhất đứng đầu.
    var shots: [ResultShot] = []

    /// Ảnh đang được xem to. Mặc định là tấm đứng đầu.
    var selectedId: Int64? = nil

    /// Đường dẫn ảnh đã giữ lại, hiện lên sau khi bấm giữ.
    var savedPath: String? = nil

    /// Đã xử lý xong (giữ hoặc bỏ) — màn hình nên đóng lại.
    var finished: Bool = false

    /// Thoát màn này để **CHỤP TIẾP**, không phải để xem thư viện.
    ///
    /// Hai lối ra khác nhau về ý định nên phải phân biệt: bấm "Lưu ảnh này" là xong
    /// việc, muốn xem thành quả → sang Thư viện. Bấm "Lưu hết & chụp tiếp" là đang
    /// giữa buổi chụp → quay lại camera ngay, đừng bắt họ bấm thêm hai nút nữa.
    var continueShooting: Bool = false

    var message: String? = nil

    var selected: ResultShot? {
        shots.first { $0.candidate.id == selectedId } ?? shots.first
    }

    var isEmpty: Bool { !loading && shots.isEmpty }

    /// Những mục mà **KHÔNG khung nào trong cả lần quay đạt nổi**.
    ///
    /// ⚠️ Lý do tồn tại: app luôn trả về 5 tấm tốt nhất — kể cả khi cả 5 đều sai
    /// hoàn toàn. Bày chúng ra mà không nói gì là **thất bại im lặng** (luật số 7
    /// của dự án): người dùng tưởng đó là thứ tốt nhất có thể đạt, trong khi thực
    /// ra họ cần quay lại với mẫu xoay đúng hướng.
    ///
    /// Cố ý KHÔNG dùng ngưỡng phải đo trên máy thật: chỉ báo khi điểm ≈ 0, tức là
    /// đã lệch quá mốc "sai hoàn toàn" — một phát biểu về cấu trúc, không phải một
    /// con số cần hiệu chỉnh.
    var failedCriteria: [FailedCriterion] {
        if shots.isEmpty { return [] }
        return Criterion.allCases.compactMap { c -> FailedCriterion? in
            guard let advice = RESULT_CRITERION_ADVICE[c] else { return nil }
            let values = shots.map { $0.candidate.parts[c.key] }
            // Chỉ xét mục ĐO ĐƯỢC ở mọi khung. Mục vắng mặt là "không đo được",
            // đã bị bỏ ra khỏi cách tính rồi, không phải "sai".
            guard !values.contains(where: { $0 == nil }) else { return nil }
            let nums = values.compactMap { $0 }
            guard nums.allSatisfy({ $0 <= 0.05 }) else { return nil }
            return FailedCriterion(label: c.label, advice: advice)
        }
    }
}

/// Một mục mà cả lần quay không có khung nào đạt.
struct FailedCriterion {
    var label: String
    var advice: String
}

/// Một khung trong số 5 ảnh đem ra cho người dùng chọn.
struct ResultShot {
    var candidate: ShotCandidate
    var image: UIImage?

    /// Điểm hiện cho người dùng: số nguyên 0-100.
    ///
    /// `en_US_POSIX` như `ShotStore.num` — máy đặt dấu phẩy cho số thập phân thì
    /// chuỗi hiển thị vẫn ra đúng một con số.
    var scoreText: String {
        String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), candidate.score)
    }
}

/// MỌI THAO TÁC NGƯỜI DÙNG CÓ THỂ LÀM Ở MÀN KẾT QUẢ.
enum ResultAction {
    /// Xem to khung có id này.
    case Select(id: Int64)

    /// Giữ tấm đang chọn, xoá hết phần còn lại.
    case KeepSelected

    /// ĐÓNG — **lưu HẾT vào thư viện** rồi quay lại chụp tiếp.
    ///
    /// ⚠️ Trước đây hành động này XOÁ SẠCH. Đổi hẳn nghĩa (quyết định sản phẩm
    /// 04/09/2026): người dùng vừa bỏ công quay 30 giây, "đóng" phải hiểu là *"để
    /// đấy đã, tôi chụp tiếp"* chứ không phải *"vứt đi"*.
    ///
    /// Muốn vứt thì vào tab Thư viện xoá cả album — ở đó có hỏi lại.
    case SaveAllAndContinue
}

/// Lời khuyên cho từng mục, kèm nhãn — bản Android là danh sách `(key, (label,
/// advice))` gõ cứng trong `ResultUiState.kt`.
///
/// ⚠️ Khác một chỗ có chủ đích: thay vì gõ cứng tên mục, bản này tra nhãn từ
/// [Criterion] — cùng nguyên tắc với `ShotStore.PART_KEYS` (*"thêm tiêu chí mới mà
/// quên sửa danh sách thì bảng phân hiện tên mục sai mà vẫn trông hợp lệ"*).
/// Nhờ vậy hai mục bản iOS có mà bản Android không (`zoom_khoangcach`,
/// `nghieng_ngang`) cũng có lời khuyên riêng thay vì bị bỏ qua âm thầm.
///
/// ⚠️ Viết theo **góc nhìn của NGƯỜI MẪU**, không theo góc nhìn màn hình — người
/// cầm máy sẽ đọc to lên cho mẫu nghe. Viết theo màn hình sẽ lộn trái-phải khi nói
/// ra miệng.
private let RESULT_CRITERION_ADVICE: [Criterion: String] = [
    .YAW: "⚠ SỬA CÁI NÀY TRƯỚC. Bảo mẫu xoay người cho giống hướng trong ảnh mẫu. Sai hướng thì mọi thứ khác đúng cũng vô ích — không có cách nào cứu bằng việc đứng đúng chỗ.",
    .SCALE: "Bạn đứng sai khoảng cách. Tiến lại gần hoặc lùi ra xa cho mẫu chiếm đúng phần khung như ảnh mẫu.",
    .CENTER: "Dịch máy sang ngang cho mẫu vào đúng vị trí như trong ảnh mẫu.",
    .ELEVATION: "Nâng máy lên hoặc hạ xuống cho khớp góc nhìn của ảnh mẫu.",
    .PITCH: "Độ nghiêng của máy chưa khớp ảnh mẫu. Chúc máy xuống hoặc hất lên cho tới khi tỉ lệ đầu-chân trông giống ảnh mẫu.",
    .POSE: "Bảo mẫu để tay chân giống ảnh mẫu.",
    .SHARPNESS: "Bảo mẫu đứng yên hơn — mọi khung đều bị nhoè do cử động.",
    .EYES_OPEN: "Mẫu đang nhắm mắt ở mọi khung hình. Bảo mẫu nhìn thẳng và giữ mắt mở.",
    .CROP: "Mép khung đang cắt đúng vào cổ tay/khuỷu/gối/cổ chân, làm chi trông như bị cụt. Lùi ra một chút hoặc chỉnh khung cho cắt vào khoảng giữa hai khớp.",
    // Hai mục riêng của bản iOS — cùng giọng văn với phần trên.
    .PERSPECTIVE: "Bạn đứng sai khoảng cách so với ảnh mẫu. Đi lại gần hoặc lùi ra xa, hoặc chỉnh zoom, cho khung giống ảnh mẫu.",
    .ROLL: "Máy đang nghiêng sang ngang. Giữ máy thẳng cho đường chân trời khớp với ảnh mẫu.",
]
