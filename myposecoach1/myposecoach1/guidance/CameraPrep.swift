import Foundation

/// CẢNH BÁO VỀ CÁCH CẦM MÁY — kiểm TRƯỚC 6 tiêu chí.
///
/// ⚠️ Vì sao tách hẳn khỏi 6 tiêu chí thay vì thêm vào thành mục thứ 7:
///
/// Sáu tiêu chí trả lời câu *"đứng ở đâu, đặt máy thế nào"*. Hai thứ trong file này
/// thì khác hẳn — chúng làm **mọi phép đo phía sau mất nghĩa**:
///
/// | Sự cố | Vì sao hỏng tận gốc |
/// |---|---|
/// | Cầm máy ngang trong khi ảnh mẫu dọc | Bố cục khác hẳn. Có đứng đúng chỗ tới đâu thì ảnh ra vẫn không giống ảnh mẫu |
/// | Đang zoom | Mục xa/gần đo bằng kích thước mẫu trong khung, nên zoom **qua được tiêu chí mà không cần bước chân nào** |
///
/// Nói cách khác: nhắc người ta "lùi lại một bước" trong khi họ đang cầm ngang máy
/// là nhắc sai việc. Phải sửa cách cầm máy trước, rồi mới nói tới chỗ đứng.
nonisolated enum CameraPrep {

    /// Zoom lệch quá mức này thì cảnh báo.
    ///
    /// Không đòi đúng 1,000: một số máy trả về 1,0000001 do làm tròn số thực, và
    /// có máy đặt tiêu cự gốc ở mức hơi khác 1. Đòi bằng tuyệt đối sẽ sinh ra cảnh
    /// báo không bao giờ tắt được.
    private static let zoomTolerance: Float = 0.05

    /// - Parameters:
    ///   - devicePortrait: máy đang cầm dọc hay ngang
    ///   - templatePortrait: ảnh mẫu là ảnh dọc hay ngang. `nil` = chưa biết
    ///   - zoomRatio: mức zoom hiện tại, 1,0 = tiêu cự gốc
    /// - Returns: câu cảnh báo, `nil` = cầm máy đang ổn
    static func warningFor(
        devicePortrait: Bool,
        templatePortrait: Bool?,
        zoomRatio: Float
    ) -> String? {
        // Hướng máy xét trước: cầm sai hướng thì zoom đúng cũng vô nghĩa.
        if let templatePortrait, devicePortrait != templatePortrait {
            return templatePortrait
                ? "Ảnh mẫu là ảnh DỌC — xoay máy về dọc rồi chụp"
                : "Ảnh mẫu là ảnh NGANG — xoay máy nằm ngang rồi chụp"
        }

        // ⚠️ ĐÃ BỎ HẲN CẢNH BÁO ZOOM (07/09/2026).
        //
        // Trước đây: ảnh mẫu không kiểm được zoom (ảnh cận, không thấy chân) mà
        // người dùng đang zoom thì báo "chạm để bỏ zoom". Nhưng cảnh báo cầm máy
        // **CHẶN TOÀN BỘ lời nhắc**, nên nó biến thành ngõ cụt: app vừa bảo
        // *"tiến lên 2 bước, HOẶC zoom vào từ từ"*, người dùng zoom, rồi bị chặn.
        //
        // Quyết định sản phẩm đã chốt: ảnh cận thì **đưa cả hai lựa chọn, không
        // thiên vị** — người dùng nhìn ảnh mẫu tự chọn đứng gần hay đứng xa rồi
        // zoom. App nói thẳng là nó không tự kiểm được, thế là đủ.

        return nil
    }
}
