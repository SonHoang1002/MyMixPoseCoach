import Foundation

/// TỈ LỆ KHUNG CHỤP — người dùng tự chọn như app camera của máy (19/09/2026).
///
/// PO: *"Tỉ lệ frame preview camera thì lấy theo các tỉ lệ tiêu chuẩn thôi … 3:4,
/// 9:16, 1:1, full"*. Khung KHÔNG còn đổi theo ảnh mẫu (FOOTGUNS 97).
///
/// ⚠️ Một tỉ lệ phải áp ĐỒNG THỜI cho bốn chỗ, lệch một chỗ là người dùng canh một
/// khung mà nhận về ảnh khung khác:
///
/// | Chỗ | Làm ở đâu |
/// |---|---|
/// | Xem trước | `CaptureScreen` — ô đúng tỉ lệ, preview layer FILL_CENTER |
/// | Phép đo live | `CaptureViewModel` — `PoseFrame.croppedToAspect` |
/// | Góc mở dọc | `CaptureController.verticalFovDeg` |
/// | Ảnh ra | `ShotSession` — `ShotStore.cropToAspect` + cắt khung xương |
///
/// Mọi tỉ lệ đều là phần GIỮA của cảm biến, nên bốn chỗ cắt cùng một vùng.
nonisolated enum TiLeKhung: String, CaseIterable {
    case BA_BON = "3:4"
    case CHIN_MUOI_SAU = "9:16"
    case VUONG = "1:1"
    /// Lấp đầy màn hình — tỉ lệ lấy theo màn hình của từng máy.
    case FULL = "Full"

    var nhan: String { rawValue }

    private var rongTrenCao: Double? {
        switch self {
        case .BA_BON: return 3.0 / 4.0
        case .CHIN_MUOI_SAU: return 9.0 / 16.0
        case .VUONG: return 1.0
        case .FULL: return nil
        }
    }

    /// Tỉ lệ ngang/dọc khi cầm DỌC. `manHinh` = ngang/dọc của vùng xem trước.
    func tiLe(manHinh: Double) -> Double { rongTrenCao ?? manHinh }

    func tiep() -> TiLeKhung {
        let all = TiLeKhung.allCases
        guard let i = all.firstIndex(of: self) else { return self }
        return all[(i + 1) % all.count]
    }

    /// Khung hình nằm ngang (cầm máy ngang) thì lật tỉ lệ cho đúng chiều.
    static func theoHuong(_ tiLeDoc: Double, rong: Int, cao: Int) -> Double {
        rong > cao ? 1.0 / tiLeDoc : tiLeDoc
    }
}
