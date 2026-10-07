import AVFoundation
import Foundation
import UIKit

// Lấy từng khung hình ra khỏi file video.
//
// Đứng thay camera khi chạy thử trên máy ảo, và **cũng chính là đường sản phẩm
// dùng ở Bước 6** — chấm điểm từng khung hình sau khi quay xong 15-30 giây.
//
// Giải mã thẳng ở kích thước nhỏ (`maximumSize` của AVAssetImageGenerator) thay
// vì giải mã cỡ đầy đủ rồi thu nhỏ: nhanh hơn nhiều và không phình bộ nhớ.
// Video 4K giải mã nguyên cỡ từng khung là đủ để hết RAM.
//
// ## Khác Android cần biết
//
// | Android | iOS |
// |---|---|
// | `MediaMetadataRetriever` | `AVAssetImageGenerator` + `AVURLAsset` |
// | `getScaledFrameAtTime(OPTION_CLOSEST_SYNC)` | `copyCGImage` với `requestedTimeToleranceBefore/After = .positiveInfinity` (chỉ nhảy tới khung khoá) |
// | `OPTION_CLOSEST` (exact) | tolerance = `.zero` (đúng khung tại mốc) |
// | `METADATA_KEY_VIDEO_ROTATION` | `track.preferredTransform` |
// | `getScaledFrameAtTime` tự áp rotation | `appliesPreferredTrackTransform = true` |
// | Trả `Bitmap` | Trả `UIImage` |
nonisolated final class VideoFrameSource {

    private let asset: AVURLAsset
    private let generator: AVAssetImageGenerator

    /// Độ dài video, mili-giây. 0 nếu không đọc được.
    let durationMs: Int64

    /// Góc xoay ghi trong video (từ preferredTransform). Điện thoại quay dọc
    /// thường lưu khung hình NẰM NGANG kèm góc xoay 90° — không xử lý thì người
    /// trong khung nằm ngang, và bộ nhận diện (vốn giả định người đứng thẳng)
    /// sẽ không tìm ra. Cùng loại bẫy với hướng ảnh từ camera, xem FOOTGUNS.md mục 10.
    let rotationDegrees: Int

    /// Kích thước khung hình SAU khi đã áp góc xoay (preferredTransform).
    let displayWidth: Int
    let displayHeight: Int

    let isValid: Bool

    private let scaledWidth: Int
    private let scaledHeight: Int

    init(file: URL, targetShortSide: Int = 480) {
        asset = AVURLAsset(url: file)
        generator = AVAssetImageGenerator(asset: asset)
        // Tự áp preferredTransform của video — khung trả về đã dựng thẳng,
        // không cần xoay lại (tương đương getScaledFrameAtTime bên Android).
        generator.appliesPreferredTrackTransform = true

        // Duration
        let seconds = CMTimeGetSeconds(asset.duration)
        durationMs = seconds.isFinite && seconds > 0 ? Int64(seconds * 1000) : 0

        // Kích thước hiển thị từ video track + preferredTransform.
        var w = 0
        var h = 0
        var rot = 0
        if let track = asset.tracks(withMediaType: .video).first {
            let natural = track.naturalSize
            let transformed = CGRect(origin: .zero, size: natural).applying(track.preferredTransform)
            w = Int(abs(transformed.width).rounded())
            h = Int(abs(transformed.height).rounded())
            // preferredTransform: sin/cos của góc quay. 90° CW ↔ rotationDegrees=90.
            let t = track.preferredTransform
            let angleRad = atan2(Double(t.b), Double(t.a))
            let angleDeg = (angleRad * 180.0 / Double.pi).rounded()
            rot = Int(((angleDeg.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360))
        }
        displayWidth = w
        displayHeight = h
        rotationDegrees = rot
        isValid = durationMs > 0 && w > 0 && h > 0

        // Quy đổi cạnh ngắn về targetShortSide — công thức y hệt bản Android.
        let dw = max(w, 1)
        let dh = max(h, 1)
        let shortSide = min(dw, dh)
        let factor = shortSide <= targetShortSide ? 1.0 : Double(targetShortSide) / Double(shortSide)
        scaledWidth = max(Int((Double(dw) * factor).rounded()), 1)
        scaledHeight = max(Int((Double(dh) * factor).rounded()), 1)
        generator.maximumSize = CGSize(width: scaledWidth, height: scaledHeight)
    }

    /// Khung hình tại thời điểm [timeMs]. Trả nil nếu không lấy được.
    ///
    /// `appliesPreferredTrackTransform = true` đã tự áp góc xoay của video,
    /// nên khung hình trả về đã dựng thẳng — không cần xoay lại.
    ///
    /// - Parameter exact: `false` (mặc định) = khung khoá gần nhất (nhanh, như
    ///   `OPTION_CLOSEST_SYNC`); `true` = đúng khung tại mốc (như `OPTION_CLOSEST`)
    ///   — dùng cho bước CẮT LẠI 5 ảnh cuối ở độ phân giải cao.
    func frameAt(timeMs: Int64, exact: Bool = false) -> UIImage? {
        // ⚠️ ĐÂY LÀ THỦ PHẠM CHÍNH CỦA VIỆC LỌC ẢNH CHẬM (Android, sửa 04/09/2026).
        //
        // Tolerance lớn (default) = chỉ nhảy tới khung khoá gần nhất, không giải
        // mã lại — nhanh hơn hàng chục lần so với giải mã lại từ khung khoá gần
        // nhất trở đi. Quét 30 giây với bước 250ms không làm sập bộ nhớ.
        //
        // ĐÁNH ĐỔI: chỉ lấy được khung khoá, tức khoảng 1 khung mỗi giây. Chấp
        // nhận được, vì bộ giữ khung vốn đã bắt hai ảnh phải cách nhau ít nhất
        // 0,9 giây (`BestShotBuffer.minGapMs`).
        //
        // [exact] = true dùng cho bước CẮT LẠI 5 ảnh cuối: ở đó chỉ có 5 lần gọi
        // nên chậm không đáng kể, mà cần đúng khung.
        if exact {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
        } else {
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
        }

        let time = CMTime(value: timeMs, timescale: 1000)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            NSLog("VideoFrameSource: Không lấy được khung hình tại \(timeMs)ms — \(error)")
            return nil
        }
    }

    /// Giải phóng. Không có `release()` như MediaMetadataRetriever — huỷ generator
    /// là đủ. Giữ method để giữ nguyên API gọi của tầng trên.
    func close() {
        generator.cancelAllCGImageGeneration()
    }
}
