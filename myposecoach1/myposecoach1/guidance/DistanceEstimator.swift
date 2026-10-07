import Foundation

/// ƯỚC LƯỢNG KHOẢNG CÁCH TỪ MÁY TỚI MẪU, tính bằng MÉT.
///
/// ## Dùng để làm gì
///
/// Chỉ để nói ra **số bước chân**. Người cầm máy đang nhìn màn hình, chân không tự
/// biết đi bao xa — nên đây là mục duy nhất cần con số. Mọi mục khác đều có phản hồi
/// ngay trên màn hình nên chỉ cần *"làm từ từ đến khi tích sáng"*.
///
/// ## Công thức
///
/// ```
///     d = C × zoom × H_thật / tỉ_lệ_trong_khung
/// ```
///
/// | | Lấy từ đâu |
/// |---|---|
/// | `zoom` | camera `zoomRatio` — biết chính xác |
/// | `H_thật` | `worldLandmarks`, tính bằng MÉT — riêng cho từng người |
/// | `tỉ_lệ_trong_khung` | đã đo sẵn ở tầng đo đạc |
/// | `C` | [lensConstant] — hằng số duy nhất phải giả định |
///
/// ## Vì sao KHÔNG đọc thông số ống kính từ phần cứng
///
/// Đọc kích thước cảm biến + tiêu cự thì ra góc nhìn chính xác, nhưng phải xử lý vô
/// số biến thể máy, ống kính kép/ba, và các máy khai báo sai. Quyết định 04/09/2026:
/// **bỏ hướng đó**.
///
/// Thay bằng một hằng số, vì ống kính chính của điện thoại thực tế **rất thống nhất**
/// — quanh 24-28mm quy đổi tại 1,0x.
///
/// ## Đã kiểm trên ảnh thật
///
/// 13 tấm, cùng một người, khoảng cách đo bằng thước (1m / 2,5m / 4m):
///
/// ```
///     sai số trung bình  16%
///     sai số lớn nhất    39%   (hai tấm nghi là không thật sự đứng đúng vạch)
/// ```
///
/// ⚠️ 16% nghe nhiều nhưng **đích đến chỉ là "1 bước hay 2 bước"**. Vì vậy hàm này
/// **chỉ được dùng để đếm bước, KHÔNG được hiện số mét cho người dùng**.
nonisolated enum DistanceEstimator {

    /// Hằng số ống kính, hiệu chuẩn từ 13 ảnh thật.
    ///
    /// Nó gộp góc nhìn của ống kính chính ở mức zoom 1,0x. Đo được 0,678 với độ lệch
    /// chuẩn 0,116 (biến thiên 17%).
    private static let lensConstant = 0.678

    /// Bước chân khi NHÍCH CHỖ ĐỨNG, mét.
    ///
    /// Người lớn đi bình thường ~0,75m. Vừa cầm máy vừa nhìn màn hình thì bước rụt
    /// lại đáng kể, nên lấy **0,6m**.
    private static let stepMeters = 0.6

    /// KHOẢNG CÁCH TỐI THIỂU theo lớp ảnh, mét.
    ///
    /// ⚠️ Đây là **quyết định sản phẩm, không phải số đo** (chốt 04/09/2026).
    ///
    /// Căn cứ: chụp ở 1x hiếm khi ra ảnh đẹp — đứng gần thì phối cảnh làm phồng phần
    /// gần ống kính. Công thức của dân chụp ảnh là **lùi ra một khoảng rồi zoom lên**.
    ///
    /// Với ảnh chân dung, mốc này còn **thay thế** cho phép đo độ méo mà lớp đó không
    /// có (xem `FramingClass.seesLegs`).
    static func minStandoffMeters(_ framing: FramingClass) -> Double {
        switch framing {
        case .head, .chest: return 1.5
        case .half: return 2.0
        case .knee: return 2.5
        case .full: return 3.0
        }
    }

    /// Hệ số ống kính `C = 1 / (2·tan(vFOV₁ₓ/2))` tính từ GÓC MỞ THẬT của máy (19/09/2026).
    ///
    /// [lensConstant] là số giả định cho ống kính điện thoại phổ thông (vFOV ~73°).
    /// Máy có ống kính khác, hoặc người dùng chọn khung 1:1 (cắt trên dưới nên góc mở
    /// dọc hẹp lại), thì hằng số đó sai theo. Có góc mở thật thì dùng góc mở thật.
    ///
    /// - Parameter vFovDeg: góc mở dọc ĐANG DÙNG (đã tính zoom và tỉ lệ khung), độ
    /// - Returns: `nil` khi số vô lý — lúc đó lùi về [lensConstant]
    static func heSoOngKinh(vFovDeg: Double?, zoomRatio: Float) -> Double? {
        guard let v = vFovDeg else { return nil }
        if v < 10.0 || v > 130.0 { return nil }
        let tanNua1x = tan(v * Double.pi / 180.0 / 2.0) * Double(zoomRatio)
        return tanNua1x <= 1e-6 ? nil : 1.0 / (2.0 * tanNua1x)
    }

    /// Khoảng cách hiện tại, mét. `nil` khi thiếu dữ kiện.
    ///
    /// - Parameters:
    ///   - scaleInFrame: chiều cao mốc đo, theo tỉ lệ chiều cao khung hình
    ///   - realHeightMeters: chiều cao THẬT của chính mốc đó, từ `worldLandmarks`
    ///   - zoomRatio: mức zoom hiện tại của camera (1,0 = không zoom)
    ///   - heSo: từ [heSoOngKinh]. `nil` = dùng [lensConstant].
    static func estimate(
        scaleInFrame: Double?,
        realHeightMeters: Double?,
        zoomRatio: Float,
        heSo: Double? = nil
    ) -> Double? {
        guard let s = scaleInFrame else { return nil }
        guard let h = realHeightMeters else { return nil }
        // Mốc quá nhỏ trong khung hoặc chiều cao thật vô lý -> phép chia nổ tung.
        if s < 0.02 || h < 0.05 || h > 3.0 { return nil }
        return (heSo ?? lensConstant) * Double(zoomRatio) * h / s
    }

    /// Đổi quãng đường cần đi thành SỐ BƯỚC, dạng chữ.
    ///
    /// Dưới 0,4m thì không nói số: sai số của phép đo lớn hơn con số định nói, mà nói
    /// "nửa bước" thì người ta cũng không làm chính xác được.
    ///
    /// - Parameter meters: quãng đường cần đi, luôn dương
    /// - Returns: cụm từ để ghép vào câu, ví dụ "2 bước"
    static func stepsPhrase(_ meters: Double) -> String {
        let steps = meters / stepMeters
        if meters < 0.4 { return "một chút" }
        if steps < 1.5 { return "1 bước" }
        if steps < 2.5 { return "2 bước" }
        if steps < 3.5 { return "3 bước" }
        return "một quãng nữa"
    }
}
