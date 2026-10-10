import Foundation

/**
 * Số liệu khuôn mặt. Android lấy từ ML Kit; iOS lấy từ `FaceAnalyzer`
 * (`VNDetectFaceRectanglesRequest`) hoặc `nil` khi không thấy mặt. Mọi trường có
 * thể `null` — không thấy mặt là chuyện bình thường (mẫu quay lưng), không phải
 * lỗi.
 */
struct FaceInfo {


    /**
     * Góc mặt quay trái/phải, ĐỘ. 0 = nhìn thẳng vào máy.
     *
     * Chính xác hơn hẳn góc thân với ảnh chân dung (~3-5° so với ~8-10°) vì mặt có
     * nhiều mốc rõ ràng hơn cặp vai. Đó là lý do `FramingClass.yawSource` chỉ định
     * CHEST/HEAD dùng nguồn này.
     */
    var yawDeg: Double?


    /**
     * Mắt có mở không, 0..1. Lấy **giá trị NHỎ HƠN** của hai mắt.
     *
     * Lấy nhỏ hơn là cố ý: nhắm một mắt cũng là ảnh hỏng. Lấy trung bình sẽ cho
     * qua những tấm nháy một bên.
     *
     * iOS trả `nil`: Vision không đo được độ mở mắt đáng tin (`VNDetectFaceRectanglesRequest`
     * không có chỉ số này). Mục MẮT MỞ là hậu kỳ → `TemplateProfile` tự bỏ và ghi
     * lý do, đúng luật "không đo được thì bỏ ra, không trừ điểm".
     */
    var eyesOpen: Double?
}
