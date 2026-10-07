import Foundation
import UIKit

/// Trạng thái MÀN CHỤP THẬT — camera thật, quay video thật.
///
/// Nguồn hình là camera thật; mọi thứ phía sau (đo, chấm điểm, chọn 5 ảnh) đọc từ
/// file video. Mọi thứ phía sau (đo, chấm điểm, chọn 5 ảnh) dùng chung code.
struct CaptureUiState {
    /// Độ giống ảnh mẫu ngay lúc này, 0..100. `nil` = chưa đo được.
    var matchPercent: Int? = nil

    /// Đã đủ giống để chuẩn bị tạo dáng và bấm quay.
    var readyToPose = false

    /// Người dùng bật chế độ tự động đếm ngược rồi quay.
    var autoMode = false

    /// Giây còn lại của đồng hồ đếm ngược. `nil` = chưa đếm.
    var countdown: Int? = nil

    /// Chế độ chụp: người khác cầm máy, hay tự chụp qua gương.
    var mode: ShootMode = .NGUOI_KHAC

    // --- Ảnh mẫu ---
    var templateName = ""
    var templateThumb: UIImage? = nil
    var templateFraming: FramingClass? = nil
    var templateError: String? = nil
    var analyzingTemplate = true

    /// Ảnh mẫu này sẽ được chấm theo những tiêu chí nào, và bỏ qua gì vì sao.
    /// Hiện lên màn hình để người dùng biết app đang soi cái gì.
    var criteriaSummary: [String] = []

    /// TRẠNG THÁI SỐNG của từng tiêu chí — nguồn duy nhất để vẽ danh sách dấu tích.
    ///
    /// ⚠️ Trước đây chỗ này chỉ là `[String]` (danh sách TÊN), nên bảng tiêu chí
    /// trên màn hình **nằm im**: đạt hay không đều hiện như nhau. Đây đúng thứ
    /// `CLAUDE.md` đã cảnh báo trước — *"danh sách 6 điều kiện phải SỐNG"*.
    var criteria: [CriterionStatus] = []

    /// ⚠️ TẠM — số đo thật của mấy mục hay sai, hiện lên màn hình.
    ///
    /// Có vì một lý do cụ thể: PO báo *"máy liên tục nhắc zoom lại gần và hạ máy
    /// xuống, càng hạ càng sai"* với một ảnh mẫu chụp thẳng chính diện. Không tái
    /// hiện được trên máy dev, mà đoán thêm một vòng nữa thì tốn một buổi test.
    ///
    /// Hiện thẳng `ảnh mẫu / khung hình` của từng mục thì buổi test sau nói ngay
    /// được mục nào lệch và lệch bao nhiêu. Gỡ sau khi tìm ra.
    var debugDo: String? = nil

    /// ⚠️ TẠM — góc máy đo bằng CẢM BIẾN đặt cạnh góc máy SUY TỪ ẢNH của cùng khung
    /// hình, chữ to để đọc được khi đang cầm máy (14/09/2026).
    ///
    /// Trả lời đúng một câu hỏi còn treo: phép suy góc từ trục thân có lệch trên
    /// ảnh chụp bằng điện thoại không. Video test 13/09/2026 cầm máy thẳng mà phép
    /// suy đọc −14 … −23°, nhưng lúc đó không có số cảm biến để biết người chụp có
    /// thật sự đang chúc hay không.
    ///
    /// - Hai số gần nhau → phép suy đúng.
    /// - Số suy từ ảnh thấp hơn đều một khoảng → bị lệch, phải hiệu chỉnh — nếu không
    ///   ảnh chụp bằng điện thoại mà người dùng tự nhập sẽ bị hướng dẫn sai góc.
    ///
    /// Gỡ sau khi có kết quả.
    var debugGocMay: String? = nil

    /// Ảnh mẫu là ảnh dọc hay ngang. `nil` = chưa biết.
    var templatePortrait: Bool? = nil

    // --- Camera ---
    var cameraReady = false
    var cameraError: String? = nil

    /// Máy yếu có thể không chạy nổi nhận diện trong lúc quay — phải báo, không im lặng.
    var liveDetectionActive = true

    // --- Nhận diện thời gian thực ---
    var pose: PoseFrame = .empty
    var personDetected = false
    var visiblePoints = 0
    var bodyYawDeg: Double? = nil
    var liveFraming: FramingClass? = nil
    var inferenceMs: Int64 = 0

    /// Kích thước khung hình đưa vào nhận diện — cần để vẽ khung xương đúng chỗ.
    var frameWidth = 0
    var frameHeight = 0

    // --- Engine hướng dẫn ---

    /// Câu nhắc đang hiện. Mỗi lúc đúng MỘT câu. `nil` = không nhắc gì.
    var cue: String? = nil

    /// Cảnh báo về CÁCH CẮM MÁY (xoay ngang, đang zoom).
    ///
    /// Tách khỏi 6 tiêu chí vì nó làm **mọi phép đo phía sau mất nghĩa** — nhắc
    /// "lùi lại một bước" trong lúc người ta cầm ngang máy là nhắc sai việc.
    var prepWarning: String? = nil

    /// Câu đang hiện là câu để ĐỌC TO CHO MẪU NGHE.
    var cueForModel = false

    /// Đủ điều kiện để bấm quay chưa.
    var readyToCapture = false

    /// Đã giữ ổn định được bao lâu, mili giây.
    var stableForMs: Int64 = 0

    /// Máy đang cầm dọc hay ngang.
    var devicePortrait = true

    /// Mức zoom hiện tại. 1,0 = tiêu cự gốc.
    var zoomRatio: Float = 1

    // --- Quay / chụp liên tục ---

    /// Đang ở chế độ CHỤP LIÊN TỤC thay vì quay video.
    ///
    /// Hai đường này không thay cho nhau: video bắt được mọi khoảnh khắc trong
    /// 15-30 giây nhưng mỗi ảnh là khung cắt ra; chụp liên tục chỉ bắt 8 khoảnh
    /// khắc nhưng mỗi ảnh là **ảnh chụp thật, full độ phân giải**.
    var burstMode = false

    /// Số ảnh đã chụp xong trong loạt hiện tại.
    var burstTaken = 0

    var recording = false
    var recordedMs: Int64 = 0

    // --- Chấm điểm sau khi quay ---
    var processing = false
    var processProgress = 0.0
    var processNote = ""

    /// Đã chốt xong danh sách ảnh — chuyển sang màn xem lại.
    var finishedSession: URL? = nil

    /// Quay đủ lâu để có gì mà chọn chưa.
    var canStop: Bool { recordedMs >= Self.MIN_RECORD_MS }

    /// Ngắn hơn mức này thì gần như không có khung nào khác nhau để chọn.
    static let MIN_RECORD_MS: Int64 = 3_000

    /// Tự dừng ở mốc này. Tài liệu sản phẩm chốt 15-30 giây; quay dài hơn chỉ
    /// tốn chỗ và làm bước chấm điểm lâu, không cho thêm ảnh đẹp nào.
    static let MAX_RECORD_MS: Int64 = 30_000
}

/// MỌI THAO TÁC NGƯỜI DÙNG CÓ THỂ LÀM Ở MÀN CHỤP.
///
/// Tách khỏi [CaptureUiState] để SwiftUI chỉ render khi TRẠNG THÁI đổi, còn thao
/// tác thì tự nó không làm thay đổi gì cả — đúng hình ba lớp state / action / effect.
nonisolated enum CaptureAction {
    case toggleRecording

    /// Người dùng bấm vào cảnh báo zoom để đưa zoom về 1,0x.
    case resetZoom
}
