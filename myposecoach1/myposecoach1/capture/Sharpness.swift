import Foundation
import CoreGraphics
import UIKit

/// ĐỘ NÉT của một khung hình.
///
/// ⚠️ Đây KHÔNG phải phép chấm chất lượng ảnh nói chung. Người dùng đã chốt bỏ
/// qua ràng buộc rung tay và ánh sáng, nên app không đo phơi sáng, không đo tương
/// phản, không nhắc gì về ánh sáng.
///
/// Cái duy nhất đo ở đây là **nhoè do CHỦ THỂ cử động** — thứ nảy sinh từ chính
/// cách sản phẩm hoạt động: quay video 15-30 giây rồi cắt khung ra. Mẫu vung tay
/// hay xoay người trong lúc quay thì đúng khung đó bị nhoè, dù máy đứng yên tuyệt
/// đối và ánh sáng hoàn hảo. Không lọc thì hoàn toàn có thể trả về 5 tấm nhoè.
///
/// Cách đo: **phương sai của toán tử Laplace**. Nói nôm na là đếm xem trong ảnh có
/// bao nhiêu chỗ chuyển màu gắt. Ảnh nét có nhiều đường biên rõ → số lớn. Ảnh nhoè
/// thì mọi thứ nhoè vào nhau → số nhỏ.
///
/// Con số trả về **không có đơn vị và không so được giữa các phiên khác nhau**
/// (ảnh nhiều hoạ tiết luôn cho số cao hơn ảnh nền trơn, dù cả hai đều nét). Chỉ
/// dùng để so các khung TRONG CÙNG một lần quay với nhau — đúng việc đang cần.
nonisolated enum Sharpness {

    /// Thu nhỏ về bề ngang này trước khi tính.
    ///
    /// Bắt buộc phải thu nhỏ, vì hai lý do:
    ///  - Tính trên ảnh gốc 12 triệu điểm ảnh ở 10 khung/giây thì máy không kịp.
    ///  - Ảnh to luôn cho số lớn hơn ảnh nhỏ, nên nếu các khung không cùng kích
    ///    thước thì số đo không so được với nhau. Ép cùng bề ngang là chuẩn hoá luôn.
    private static let workWidth = 160

    /// - Returns: số càng lớn càng nét. Trả 0 khi không tính được.
    static func of(_ image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0.0 }
        return of(cgImage)
    }

    /// - Returns: số càng lớn càng nét. Trả 0 khi không tính được.
    static func of(_ cgImage: CGImage) -> Double {
        let sourceW = cgImage.width
        let sourceH = cgImage.height
        if sourceW < 8 || sourceH < 8 { return 0.0 }

        // Ép cùng bề ngang: ảnh to luôn cho số Laplace lớn hơn ảnh nhỏ dù cùng độ nét.
        let w = workWidth
        let h = max(8, Int(Int64(workWidth) * Int64(sourceH) / Int64(sourceW)))
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel

        var pixels = [UInt8](repeating: 0, count: bytesPerRow * h)
        let drew: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let info = CGImageAlphaInfo.premultipliedLast.rawValue
            guard let ctx = CGContext(
                data: base,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: info
            ) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        if !drew { return 0.0 }

        // Chuyển sang mức xám. Hệ số theo độ nhạy của mắt người với từng màu.
        var gray = [Double](repeating: 0, count: w * h)
        for i in 0..<gray.count {
            let o = i * bytesPerPixel
            gray[i] = 0.299 * Double(pixels[o]) +
                0.587 * Double(pixels[o + 1]) +
                0.114 * Double(pixels[o + 2])
        }

        // Toán tử Laplace 3x3: lấy điểm giữa nhân 4 rồi trừ đi 4 điểm xung quanh.
        // Vùng màu phẳng cho ra ~0; chỗ có đường biên cho ra số lớn.
        var sum = 0.0
        var sumSq = 0.0
        var n = 0
        var y = 1
        while y < h - 1 {
            let row = y * w
            var x = 1
            while x < w - 1 {
                let i = row + x
                let v = 4 * gray[i] - gray[i - 1] - gray[i + 1] - gray[i - w] - gray[i + w]
                sum += v
                sumSq += v * v
                n += 1
                x += 1
            }
            y += 1
        }
        if n == 0 { return 0.0 }

        let mean = sum / Double(n)
        return (sumSq / Double(n)) - mean * mean
    }

    /// Quy một loạt số đo thô về thang 0..1, trong đó 1 = nét nhất của loạt này.
    ///
    /// Phải làm theo loạt vì số thô không có mốc tuyệt đối. Cả loạt nét ngang nhau
    /// thì trả về 1.0 hết — đúng ý: khi không có gì để phân biệt, đừng phân biệt.
    static func normalize(_ values: [Double]) -> [Double] {
        if values.isEmpty { return [] }
        guard let maxValue = values.max(), let minValue = values.min() else {
            return values.map { _ in 1.0 }
        }
        // Chênh lệch không đáng kể => coi như nhau. Ngưỡng tương đối, không tuyệt đối.
        if maxValue <= 0.0 || (maxValue - minValue) < maxValue * 0.05 {
            return values.map { _ in 1.0 }
        }
        return values.map { min(max(($0 - minValue) / (maxValue - minValue), 0.0), 1.0) }
    }
}
