import Foundation

/// Trạng thái hiển thị của một mục trong danh sách 6 điều kiện.
///
/// ⚠️ [UNMEASURED] KHÔNG phải là "chưa đạt". Đây là luật số 4 của dự án: *không đo
/// được khác với sai*. Mục không đo được thì bị **bỏ ra**, không bị trừ điểm và
/// không sinh lời nhắc — vì không có gì để nhắc.
nonisolated enum GateState {
    /// Chưa đo được ở khung hình này. Hiện dấu gạch, không phải dấu X.
    case UNMEASURED

    /// Đang lệch quá nhiều và đã lệch đủ lâu. Đây là mục sinh ra lời nhắc.
    case FAILING

    /// Vùng đệm: đã tốt hơn mức đáng nhắc nhưng chưa đủ tốt để công nhận.
    ///
    /// Trạng thái này tồn tại **chỉ để chống nhấp nháy**. Không có nó thì người
    /// đứng ngay ranh giới sẽ thấy tích bật/tắt liên tục theo từng khung hình.
    case GREY

    /// ĐẠT. Hiện dấu tích.
    case PASSING
}

/// CỔNG TRẠNG THÁI CỦA MỘT TIÊU CHÍ — vùng trễ 3 mức, có chống rung và chống kẹt.
///
/// Đây là phần được viết lại có chủ đích từ `CriterionGate` của bản Swift: khó viết
/// đúng từ đầu và dễ đẻ ra lỗi kiểu *"app đứng im mà không ai hiểu vì sao"*.
///
/// Bốn hành vi phải có, thiếu cái nào cũng hỏng theo một kiểu riêng:
///
/// | Cơ chế | Thiếu nó thì |
/// |---|---|
/// | Vùng trễ 3 mức | tích nhấp nháy khi đứng ngay ranh giới |
/// | Chờ đủ lâu mới đổi (debounce) | một khung hình nhiễu cũng lật trạng thái |
/// | Khoá mục đã đạt | đã đạt rồi vẫn tuột vì rung tay |
/// | Chống kẹt (stall) | **app đứng im vĩnh viễn**, không nhắc gì mà cũng không cho chụp |
///
/// ⚠️ Lớp này là **logic thuần, không đụng AVFoundation/CoreMotion** — cố ý, để
/// kiểm được bằng unit test. *Hành vi* kiểm bằng test, *con số* phải đo trên máy thật.
nonisolated final class CriterionGate {

    let criterion: Criterion

    private(set) var state: GateState = .UNMEASURED

    /// Đã đạt và đang được giữ khoá. Chỉ mở khi lệch quá [Band.unlock] hoặc bị kẹt quá lâu.
    private(set) var locked: Bool = false

    /// Vừa bị mở khoá vì kẹt. Khi cờ này bật, vùng xám cũng bị coi là FAILING để
    /// **nhắc lại** — nếu không thì mục vừa mở khoá sẽ lại rơi vào im lặng, đúng
    /// cái tình trạng mà chống kẹt sinh ra để phá.
    private var stalled: Bool = false

    /// Mốc thời gian bắt đầu chuỗi "không đo được" hiện tại. `nil` = đang đo được.
    ///
    /// ⚠️ VÌ SAO CẦN: ảnh mẫu quyết định danh sách tiêu chí MỘT LẦN. Nếu ảnh mẫu là
    /// lớp ngang gối, app bật mục zoom — nhưng người cầm máy lấy khung chặt hơn một
    /// chút là **đầu gối ra ngoài khung**, mục đó nằm im ở dấu gạch VĨNH VIỄN.
    ///
    /// Không có gì sai về mặt tính toán: không đo được thì không chấm, đúng quy tắc
    /// số 4. Nhưng với người dùng thì đó là **ngõ cụt im lặng** — quy tắc số 7 cấm.
    /// Đủ lâu thì phải nói ra: *"Chưa kiểm được zoom — lùi ra cho thấy đầu gối"*.
    private var unmeasuredSinceMs: Int64?

    private var belowAcceptSince: Int64?
    private var aboveEnterSince: Int64?
    private var greySince: Int64?

    init(_ criterion: Criterion) {
        self.criterion = criterion
    }

    /// Đã "không đo được" đủ lâu để cần giải thích cho người dùng chưa.
    func unmeasuredTooLong(_ nowMs: Int64) -> Bool {
        guard let since = unmeasuredSinceMs else { return false }
        return nowMs - since >= GuidanceTiming.STALL_TIMEOUT_MS
    }

    /// Nạp số đo của một khung hình.
    ///
    /// - Parameter deviation độ lệch TUYỆT ĐỐI so với ảnh mẫu, cùng đơn vị với [band].
    ///        `nil` = khung này không đo được mục đó.
    /// - Parameter nowMs mốc thời gian của khung hình, mili giây.
    func update(deviation: Double?, band: Band, nowMs: Int64) -> GateState {
        if deviation == nil {
            // Không đo được: dừng mọi đồng hồ, KHÔNG coi là sai.
            // Mục đã khoá thì giữ nguyên tích — mất dấu một lúc không xoá được
            // việc người ta đã đứng đúng chỗ.
            belowAcceptSince = nil
            aboveEnterSince = nil
            greySince = nil
            // Đếm giờ để biết khi nào cần GIẢI THÍCH vì sao chưa đo được. Mục đã
            // khoá thì không đếm — nó vẫn đang hiện tích, chẳng có gì bí ẩn.
            if !locked && unmeasuredSinceMs == nil { unmeasuredSinceMs = nowMs }
            state = locked ? .PASSING : .UNMEASURED
            return state
        }

        let d = deviation!

        // Đo được rồi thì xoá đồng hồ giải thích.
        unmeasuredSinceMs = nil

        if locked {
            if d > band.unlock {
                // Lệch hẳn ra ngoài: mở khoá, xét lại từ đầu ngay trong lượt này.
                locked = false
                greySince = nil
            } else if d > band.enter {
                // ⚠️ TRÔI QUÁ MỨC ĐÁNG NHẮC mới tính là kẹt. So với [Band.enter],
                // KHÔNG so với [Band.accept].
                //
                // Bản cũ so với `accept` và mở khoá sau 2,5 giây. Nhưng khoảng giữa
                // `accept` và `enter` chính là **vùng đệm chống nhấp nháy** — cầm
                // máy trên tay thì số đo nằm trong đó gần như thường trực. Kết quả:
                // mọi tích vừa xanh được vài giây là **tự rụng**, người dùng phải
                // làm lại từ đầu mãi không xong.
                let since = greySince ?? nowMs
                if greySince == nil { greySince = since }
                if nowMs - since >= GuidanceTiming.STALL_TIMEOUT_MS {
                    locked = false
                    stalled = true
                    greySince = nil
                } else {
                    state = .PASSING
                    return state
                }
            } else {
                // Trong vùng đệm hoặc vẫn đạt: GIỮ NGUYÊN TÍCH, không đếm giờ gì cả.
                greySince = nil
                state = .PASSING
                return state
            }
        }

        if d <= band.accept {
            aboveEnterSince = nil
            greySince = nil
            stalled = false
            let since = belowAcceptSince ?? nowMs
            if belowAcceptSince == nil { belowAcceptSince = since }
            if nowMs - since >= GuidanceTiming.CUE_EXIT_HOLD_MS {
                locked = true
                state = .PASSING
            } else {
                // Đã tốt nhưng chưa giữ đủ lâu để công nhận.
                state = .GREY
            }
        } else if d > band.enter {
            belowAcceptSince = nil
            greySince = nil
            let since = aboveEnterSince ?? nowMs
            if aboveEnterSince == nil { aboveEnterSince = since }
            // ⚠️ Vừa mở khoá vì kẹt thì nhắc NGAY, không chờ thêm lần nữa: nó
            // đã trôi suốt cả khoảng chống kẹt rồi, bắt chờ tiếp là kéo dài
            // đúng cái im lặng mà cơ chế này sinh ra để phá.
            if stalled || nowMs - since >= GuidanceTiming.CUE_ENTER_HOLD_MS {
                state = .FAILING
            } else {
                // Chưa lệch đủ lâu — có thể chỉ là một khung nhiễu.
                state = .GREY
            }
        } else {
            // Vùng xám thật sự — CHƯA khoá.
            //
            // ⚠️ ĐÂY mới là chỗ app có thể đứng im vĩnh viễn: mục chưa bao giờ đạt,
            // nằm lì trong vùng đệm nên không sinh câu nhắc nào, và cũng không bao
            // giờ đóng tích. Nằm quá lâu thì phải nhắc.
            belowAcceptSince = nil
            aboveEnterSince = nil
            let since = greySince ?? nowMs
            if greySince == nil { greySince = since }
            if stalled || nowMs - since >= GuidanceTiming.STALL_TIMEOUT_MS {
                stalled = true
                state = .FAILING
            } else {
                state = .GREY
            }
        }
        return state
    }

    /// Về trạng thái ban đầu. Gọi khi đổi ảnh mẫu hoặc vào lại màn hình.
    func reset() {
        state = .UNMEASURED
        unmeasuredSinceMs = nil
        locked = false
        stalled = false
        belowAcceptSince = nil
        aboveEnterSince = nil
        greySince = nil
    }
}
