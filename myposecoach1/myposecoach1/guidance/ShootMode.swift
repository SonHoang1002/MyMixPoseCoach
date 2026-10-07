import Foundation

/// AI ĐANG CẦM MÁY, và hình có bị lật gương không.
///
/// Hai câu hỏi này đi cùng nhau vì cùng đổi theo một lựa chọn của người dùng, và
/// mỗi câu đổi một thứ khác hẳn:
///
/// | | Ai cầm máy | Hình có lật không |
/// |---|---|---|
/// | [NGUOI_KHAC] | Người thứ hai | Không |
/// | [TU_CHUP_GUONG] | **Chính người mẫu** | **Có** — do gương, không phải do app |
///
/// ## Vì sao "ai cầm máy" đổi được câu chữ
///
/// Cả hệ thống hướng dẫn dựng trên giả định HAI người: câu về mẫu được gắn biểu
/// tượng loa để người cầm máy **đọc to lên**, và app đóng băng các mục về máy trong
/// lúc họ nói (vì lúc đó họ hạ máy xuống).
///
/// Tự chụp thì chỉ có MỘT người, và người đó **nhìn thấy màn hình**. Câu *"Bảo mẫu
/// xoay người"* thành vô nghĩa — phải là *"Xoay người"*. Không có ai để đọc to, và
/// cũng không cần đóng băng vì máy vẫn đang giơ.
///
/// ## Vì sao "lật gương" là chuyện riêng
///
/// Xem `PoseFrame.mirrored()`. Tóm tắt: ảnh gương làm bộ nhận diện gọi tay PHẢI
/// thật là `LEFT_WRIST`, nên phải lật khung xương về không gian chuẩn trước khi đo.
/// Việc lật đó lại **đảo chiều** hai câu nhắc — lệch trái/phải và nghiêng ngang.
///
/// ⚠️ Chưa có chế độ camera TRƯỚC. Nó cần thêm việc khác hẳn: app tự lật khung xem
/// trước trong khi khung phân tích thì không, cộng với việc loại cánh tay cầm máy
/// khỏi phép chấm dáng.
nonisolated enum ShootMode {
    /// Người thứ hai cầm máy. Mặc định, và là luồng đã chạy từ trước tới nay.
    case NGUOI_KHAC

    /// Tự chụp bằng cách chĩa camera SAU vào gương.
    case TU_CHUP_GUONG

    /// Tự chụp bằng camera TRƯỚC, cầm trên tay.
    case TU_CHUP_CAM_TRUOC

    /// Người cầm máy có phải chính là mẫu không. Đổi GIỌNG câu nhắc.
    var tuChup: Bool { self != .NGUOI_KHAC }

    /// Hình sẽ được lưu ra có bị LẬT NGANG không. Đổi CHỮ trái/phải ở câu nhắc dáng.
    ///
    /// Gương thì do vật lý. Camera trước thì do app cố tình lật khi ghi — quyết định
    /// sản phẩm 06/09/2026: *người dùng nhìn màn hình thế nào thì muốn ảnh ra thế đó*.
    var latGuong: Bool { self != .NGUOI_KHAC }

    /// Dịch máy trên màn hình có NGƯỢC CHIỀU so với camera thường không.
    ///
    /// ⚠️ CHỖ NÀY KHÁC NHAU GIỮA HAI KIỂU TỰ CHỤP, dễ gộp nhầm:
    ///
    /// - **Soi gương** → `false`. Thế giới trong gương là một cảnh **TĨNH**: ảnh của
    ///   vật nằm cố định sau mặt gương, không đổi theo chỗ đứng người xem. App không
    ///   lật gì cả, nên dịch máy hành xử y hệt camera thường.
    /// - **Camera trước** → `true`. Chính APP lật khung xem trước. Dịch máy sang phải
    ///   làm chủ thể chạy sang phải trên màn — ngược hẳn camera thường.
    var mayNguocChieu: Bool { self == .TU_CHUP_CAM_TRUOC }

    /// Khoảng cách bị chặn ở TẦM TAY (~0,3-0,8m).
    ///
    /// Câu *"lùi lại 2 bước"* thành vô nghĩa — không ai đi lùi khỏi cánh tay mình.
    /// Phải đổi thành co/duỗi tay.
    var tamTay: Bool { self == .TU_CHUP_CAM_TRUOC }

    /// Dùng camera trước hay camera sau.
    var camTruoc: Bool { self == .TU_CHUP_CAM_TRUOC }
}
