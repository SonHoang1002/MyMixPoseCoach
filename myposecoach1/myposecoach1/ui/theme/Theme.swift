import SwiftUI

/// Chủ đề gốc của app — tương đương `PosecoachTheme` bên Android.
///
/// Bên Android `PosecoachTheme` bọc `MaterialTheme` để đổi bảng màu và kiểu chữ
/// cho các component Material. Bên SwiftUI không có khái niệm đó, nên ở đây chỉ
/// làm đúng phần có tác dụng thật: đặt màu nhấn (tint) và nền mặc định. Mọi màu
/// cụ thể vẫn lấy từ [Ds] — nguồn duy nhất, giống bên Android.
///
/// Android bản gốc dùng "dynamic color" (lấy màu theo hình nền máy, Android 12+).
/// iOS không có cơ chế tương đương, nên bỏ qua — [Ds] là bảng màu cố định theo thiết
/// kế Figma, không phụ thuộc hệ điều hành.
struct PosecoachTheme: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Ds.primary)
            .background(Ds.bg)
    }
}

extension View {
    /// Bọc một màn hình bằng chủ đề của app.
    func posecoachTheme() -> some View {
        modifier(PosecoachTheme())
    }
}

/// Kiểu chữ nền — tương đương `Typography` bên Android.
///
/// Android bản gốc chỉ khai `bodyLarge` (16pt, giãn dòng 24, letter-spacing 0,5).
/// SwiftUI đặt cỡ chữ ngay tại chỗ dùng, nên giữ ở đây một mốc tham chiếu duy
/// nhất để các màn hình khỏi lệch nhau.
enum DsTypography {
    static let bodySize: CGFloat = 16
    static let bodyLineSpacing: CGFloat = 8   // 24 - 16
    static let bodyTracking: CGFloat = 0.5
}
