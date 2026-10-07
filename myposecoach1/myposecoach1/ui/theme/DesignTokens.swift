import SwiftUI

/// Bộ mã màu và kích thước lấy từ thiết kế Figma "Photoshot Guide V1".
///
/// Gom một chỗ để mọi màn hình dùng chung. Rải màu thẳng vào từng màn là cách chắc
/// chắn nhất để sau vài lần sửa, năm màn hình có năm sắc xanh khác nhau.
nonisolated enum Ds {

    // --- Nền và bề mặt ---
    /// Nền màn hình sáng.
    static let bg = Color(hex: 0xF4F6FA)
    /// Thẻ, ô, hộp thoại.
    static let surface = Color(hex: 0xFFFFFF)
    /// Nền phụ nhạt hơn surface một chút — dùng cho ô ảnh mẫu, thanh tiến trình.
    static let surfaceMuted = Color(hex: 0xE9EDF3)

    // --- Chữ ---
    static let text = Color(hex: 0x0F1729)
    static let textMuted = Color(hex: 0x6B7280)
    static let textOnDark = Color(hex: 0xFFFFFF)

    // --- Màu nhấn ---
    /// Xanh chủ đạo: nút chính, thẻ import, thanh tiến trình.
    static let primary = Color(hex: 0x2E86FF)
    static let primaryPressed = Color(hex: 0x1D6FE0)
    /// Viên điều hướng đang chọn — xanh đen gần như đen.
    static let navActive = Color(hex: 0x141B2D)

    // --- Trạng thái ---
    static let success = Color(hex: 0x22C55E)
    static let warning = Color(hex: 0xF59E0B)
    /// Nút xoá: nền hồng nhạt, chữ đỏ — mềm hơn nút đỏ đặc, tránh doạ người dùng.
    static let dangerSoft = Color(hex: 0xFBDDE1)
    static let dangerText = Color(hex: 0xE5484D)
    /// Chấm đỏ khi đang quay.
    static let recording = Color(hex: 0xEF4444)

    // --- Lớp phủ trên camera ---
    /// Nền tối cho ô thông tin đặt trên hình camera.
    static let overlayPanel = Color(hex: 0x10151F, alpha: 0.80)
    static let overlayScrim = Color(hex: 0x000000, alpha: 0.40)

    // --- Bo góc ---
    static let rCard: CGFloat = 18
    static let rTile: CGFloat = 16
    static let rPill: CGFloat = 999
    static let rSmall: CGFloat = 10

    // --- Khoảng cách ---
    static let pageH: CGFloat = 18
    static let gap: CGFloat = 12
}

/// THƯ VIỆN CÂU CHỈ DẪN — lấy nguyên văn từ Figma.
///
/// ⚠️ Viết theo **góc nhìn của NGƯỜI CẦM MÁY** với các câu về máy, và theo **góc
/// nhìn của NGƯỜI MẪU** với các câu về mẫu ("Mẫu xoay trái" = bảo mẫu xoay, không
/// phải bảo người cầm máy). Người cầm máy đọc to câu đó lên cho mẫu nghe, nên viết
/// theo góc nhìn màn hình sẽ lộn trái-phải khi nói ra miệng.
nonisolated enum Cues {
    static let MOVE_LEFT = "Đưa sang trái"
    static let MOVE_RIGHT = "Đưa sang phải"
    static let STEP_BACK = "Lùi về sau"
    static let STEP_FORWARD = "Tiến lên trước"
    static let RAISE = "Nâng máy lên"
    static let LOWER = "Hạ máy xuống"
    static let TILT_DOWN = "Chúc máy xuống"
    static let TILT_UP = "Hất máy lên"
    static let ZOOM_IN = "Zoom in"
    static let ZOOM_OUT = "Zoom out"
    static let MODEL_TURN_LEFT = "Mẫu xoay trái"
    static let MODEL_TURN_RIGHT = "Mẫu xoay phải"
    static let MODEL_TURN_AROUND = "Mẫu quay người"
    static let READY = "Góc chuẩn rồi, giữ nguyên"
}

extension Color {
    /// Dựng màu từ mã hex 0xRRGGBB, kèm độ mờ tuỳ chọn.
    nonisolated init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
