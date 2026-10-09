import Foundation
import ImageIO
import UIKit

// NẠP ẢNH ĐÃ DỰNG ĐÚNG CHIỀU — nơi DUY NHẤT được đọc file ảnh trong app.
//
// ## Vấn đề file này giải
//
// Điện thoại chụp ảnh dọc nhưng **lưu ra file NẰM NGANG**, kèm một cờ trong phần
// thông tin ảnh (EXIF) ghi *"khi hiển thị thì xoay 90°"*. Thư viện ảnh của máy đọc
// cờ đó nên bạn thấy ảnh dựng đứng bình thường.
//
// `CGImageSourceCreateImageAtIndex()` **bỏ qua cờ đó hoàn toàn** — nó trả về đúng
// khối điểm ảnh nằm ngang.
//
// ## Vì sao điều đó phá cả dây chuyền
//
// Đo trên chính bộ ảnh chụp thử ở `test-media/5-chan-dung-zoom/`: **cả 5 tấm đều
// mang cờ EXIF = 6 (xoay 90°)**. Nếu nạp bằng cách cũ:
//
// | Bước | Chuyện xảy ra |
// |---|---|
// | Nhận diện | MediaPipe thấy **người nằm ngang**. Model huấn luyện trên người ĐỨNG — hoặc không thấy gì, hoặc trả khung xương rác |
// | Cổng kiểm | Trục thân đo ra ~90° → vượt ngưỡng 60° → **từ chối: "gần như nằm ngang, không phải dáng đứng"** |
// | Mọi phép đo | Cao/thấp thành trái/phải và ngược lại — sai trục có hệ thống |
// | Nhắc xoay máy | Ảnh dọc bị đọc thành ảnh ngang → app bảo người dùng **xoay máy ngược lại** |
//
// Lỗi hiện ra dưới dạng *"ảnh không dùng được"*, không ai đoán được nguyên nhân thật.
//
// ## Vì sao trước đây không lộ
//
// 8 ảnh mẫu cài sẵn đều tải từ mạng, đã dựng đứng sẵn, không mang cờ EXIF. Bug nằm
// im cho tới lúc có người **tự chụp bằng điện thoại rồi nhập vào** — đúng việc phải
// làm để đo ngưỡng.
//
// ## Quy tắc
//
// ⚠️ **Không gọi `CGImageSourceCreateImageAtIndex`/`UIImage(contentsOfFile:)` ở bất
// cứ đâu khác.** Cùng tinh thần với "một hàm chuẩn hoá toạ độ duy nhất": rải phép
// xoay khắp code thì sẽ có chỗ quên, mà chỗ quên đó lại không báo lỗi gì.
//
// Dùng ImageIO có sẵn trong iOS, **không thêm thư viện nào**.
//
// ## Khác Android cần biết
//
// Bản Android xoay pixels thật (`Bitmap.rotate`) rồi trả `Bitmap` đã dựng. Bản iOS
// trả `UIImage` mang `imageOrientation` theo cờ EXIF — **không vẽ lại pixels**.
// Mọi consumer trong app đi qua `VisionPose.frame(fromCGImage:)` với
// `CGImagePropertyOrientation(image.imageOrientation)` (Vision tự xoay theo
// orientation), hoặc vẽ UIImage chuẩn — nên hành vi tương đương. Tuyệt đối không
// đọc `uiImage.cgImage` rồi coi là ảnh dựng đứng.
nonisolated enum UprightBitmap {

    /// Nạp ảnh và dựng đúng chiều người xem nhìn thấy.
    ///
    /// - Parameter shortSide: cạnh ngắn mong muốn, tính bằng điểm ảnh. Truyền `nil`
    ///   để nạp nguyên cỡ. Ảnh điện thoại thường 4000×3000 — nạp nguyên cỡ chỉ để
    ///   hiện cái ảnh thu nhỏ là phí bộ nhớ và dễ tràn.
    /// - Returns: UIImage đã gắn EXIF orientation, hoặc nil nếu không đọc được.
    static func decode(file: URL, shortSide: Int? = nil) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else {
            NSLog("UprightBitmap: Không mở được file \(file.lastPathComponent)")
            return nil
        }

        // Đọc cờ EXIF + kích thước trước khi giải mã.
        var exifOrientation = 1 // kCGImagePropertyOrientation.up
        var pixelW = 0
        var pixelH = 0
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if let o = props[kCGImagePropertyOrientation] as? Int {
                exifOrientation = o
            }
            pixelW = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            pixelH = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        }
        guard pixelW > 0, pixelH > 0 else {
            NSLog("UprightBitmap: Không đọc được kích thước \(file.lastPathComponent)")
            return nil
        }

        // EXIF 5–8 làm đổi trục ngang/dọc khi hiển thị — shortSide tính theo ảnh ĐÃ dựng.
        let swapsAxes = exifOrientation >= 5 && exifOrientation <= 8
        let displayW = swapsAxes ? pixelH : pixelW
        let displayH = swapsAxes ? pixelW : pixelH

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Giữ nguyên pixels theo EXIF; orientation gắn bằng UIImage bên dưới —
            // không để ImageIO tự xoay (tránh xoay hai lần).
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceShouldCacheImmediately: true,
        ]

        if let shortSide {
            let short = min(displayW, displayH)
            guard short > 0 else { return nil }
            if short > shortSide {
                // Thumbnail maxPixelSize giới hạn cạnh DÀI — quy đổi để cạnh NGẮN
                // về `shortSide`, tương đương mục tiêu của `inSampleSize` bên Android.
                let factor = Double(shortSide) / Double(short)
                let maxPixel = Int((Double(max(displayW, displayH)) * factor).rounded())
                options[kCGImageSourceThumbnailMaxPixelSize] = max(maxPixel, 1)
            }
        }

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            NSLog("UprightBitmap: Không giải mã được \(file.lastPathComponent)")
            return nil
        }

        return UIImage(cgImage: cgImage,
                       scale: 1,
                       orientation: UIImage.Orientation(exif: exifOrientation))
    }
}

nonisolated private extension UIImage.Orientation {
    /// Ánh xạ cờ EXIF (1–8) → UIImage.Orientation. 1–4 giữ trục; 5–8 đổi trục.
    ///
    /// Tương đương `rotateByExif` bên Android — nhưng gắn orientation, không vẽ pixels.
    init(exif orientation: Int) {
        switch orientation {
        case 2: self = .upMirrored
        case 3: self = .down
        case 4: self = .downMirrored
        // Ảnh lật gương: hiếm, nhưng có thật với ảnh tự chụp bằng camera trước
        // trên một số máy. Bỏ qua thì khung xương bị lật trái-phải.
        case 5: self = .leftMirrored
        case 6: self = .right
        case 7: self = .rightMirrored
        case 8: self = .left
        default: self = .up
        }
    }
}
