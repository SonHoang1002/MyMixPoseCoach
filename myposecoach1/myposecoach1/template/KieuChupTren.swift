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

/// Ghép góc mở từ GeoCalib với tỉ lệ đầu/chân từ MediaPipe, cùng luật Android.
nonisolated enum DoanKieuTren {
    static let VFOV_RONG = 75.0
    static let TAI_CHAN_GAN = 0.45
    static let TAI_CHAN_XA = 0.35

    static func doan(vfovDeg: Double?, taiChan: Double?) -> KieuChupTren? {
        if let vfovDeg, vfovDeg >= VFOV_RONG { return .gan }
        if let taiChan, taiChan >= TAI_CHAN_GAN { return .gan }
        if let taiChan, taiChan <= TAI_CHAN_XA { return .xaZoom }
        return nil
    }

    static func tiLeTaiChan(
        _ frame: PoseFrame,
        rong: Int,
        cao: Int,
        minVisibility: Float = 0.5
    ) -> Double? {
        func phongDai(_ a: Int, _ b: Int) -> Double? {
            guard let pa = frame.at(a, minVisibility: minVisibility),
                  let pb = frame.at(b, minVisibility: minVisibility),
                  let wa = frame.world(a, minVisibility: minVisibility),
                  let wb = frame.world(b, minVisibility: minVisibility) else { return nil }
            let anh = hypot((pa.x - pb.x) * Double(rong), (pa.y - pb.y) * Double(cao))
            let dx = wa.x - wb.x, dy = wa.y - wb.y, dz = wa.z - wb.z
            let that = sqrt(dx * dx + dy * dy + dz * dz)
            return that > 1e-3 && anh > 1 ? anh / that : nil
        }
        guard let tai = phongDai(Lm.leftEar, Lm.rightEar),
              let chan = phongDai(Lm.leftAnkle, Lm.rightAnkle) else { return nil }
        return log(tai / chan)
    }
}
