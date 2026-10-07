import Foundation

/// KIỂU CHỤP TỪ TRÊN CAO — nhãn thứ hai, CHỈ cho ảnh người khác chụp gắn nhãn "trên
/// cao" (19/09/2026).
///
/// PO: *"chụp 1x — cầm máy giơ lên trên đầu, đứng gần mẫu — sẽ khác với chụp đứng trên
/// cao từ xa và zoom xuống"*. Ảnh không tự tách được với góc máy (FOOTGUNS 99), nên hỏi
/// người dùng — cùng cơ chế nhãn với góc máy (FOOTGUNS 91).
///
/// ⚠️ 1x VÀ 0.5x ĐÃ GỘP LÀM MỘT ("đứng gần"). Bản đầu có ba kiểu; đo 17 ảnh thì gần 1x
/// và góc rộng 0.5x chồng nhau hoàn toàn (FOOTGUNS 100), và khác biệt giữa hai kiểu là
/// PHONG CÁCH — người chụp nhìn màn hình là thấy. PO chốt: đứng gần thì cho zoom từ mức
/// nhỏ nhất của máy tới 1x, câu nhắc gợi ý thử 0.5–0.7x cho kiểu mắt cá.
///
/// Chỉ đổi CÂU NHẮC khoảng cách/zoom của đúng loại ảnh này. Không đụng tiêu chí nào khác.
nonisolated enum KieuChupTren: String, CaseIterable, Hashable {
    /// `zoomToiDa` = mức zoom lớn nhất được phép; `nil` = tự do (kiểu từ xa rồi zoom)
    case gan = "gan"
    case xaZoom = "xa"

    var tu: String { rawValue }

    var nhan: String {
        switch self {
        case .gan: return "Đứng gần"
        case .xaZoom: return "Từ xa rồi zoom"
        }
    }

    var goiY: String {
        switch self {
        case .gan:
            return "Giơ máy qua đầu chúc xuống, zoom 1x hoặc góc rộng 0.5x · đầu to hơn chân rõ"
        case .xaZoom:
            return "Đứng chỗ cao nhìn xuống · tỉ lệ người gần như thật, nền phẳng"
        }
    }

    var zoomToiDa: Float? {
        switch self {
        case .gan: return 1.0
        case .xaZoom: return nil
        }
    }

    static func cuaTu(_ tu: String) -> KieuChupTren? {
        // Nhãn "rong" (góc rộng) của bản đầu nay thuộc "đứng gần".
        if tu == "rong" { return .gan }
        return KieuChupTren(rawValue: tu)
    }
}
