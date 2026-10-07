import Foundation

/**
 * Số liệu khuôn mặt lấy từ ML Kit. Mọi trường có thể `null` — không thấy mặt là
 * chuyện bình thường (mẫu quay lưng), không phải lỗi.
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
     */
    var eyesOpen: Double?
}
