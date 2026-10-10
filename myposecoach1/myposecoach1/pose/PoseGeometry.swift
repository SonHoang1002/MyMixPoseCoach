import Foundation

// ĐÂY LÀ FILE MANG BẤT BIẾN QUAN TRỌNG NHẤT CỦA DỰ ÁN.
//
// Mọi nơi trong app muốn đọc toạ độ khung xương đều PHẢI đi qua đây. Không nơi
// nào được tự đọc `landmark.x` rồi tự quy đổi.
//
// Vì sao (FOOTGUNS.md mục 3): bản Android dùng Vision, trả toạ độ chuẩn hoá 0-1 với
// gốc ở góc DƯỚI-trái, trục Y hướng LÊN — nên code Swift lật y ở khắp nơi
// (`1.0 - point.y`). MediaPipe thì gốc ở góc TRÊN-trái, Y hướng XUỐNG. Nếu rải
// phép quy đổi khắp code, chỉ cần một chỗ quên là MỌI phép tính góc và mọi so
// sánh "cao hơn / thấp hơn" đảo dấu — mà app vẫn chạy bình thường, không báo lỗi
// gì, chỉ có hướng dẫn ngược chiều.
//
// Quy ước thống nhất toàn app, chốt tại đây:
//   x: 0.0 = mép TRÁI khung   →  1.0 = mép PHẢI khung
//   y: 0.0 = mép TRÊN khung   →  1.0 = mép DƯỚI khung   (y càng lớn = càng THẤP)
//
// Bản iOS chính dùng MediaPipe cùng model .task với Android nên đã đúng quy ước;
// `VisionPose.swift` chỉ còn là fallback và tự đổi hệ tọa độ về quy ước này.

/// Một điểm trên khung hình, theo đúng quy ước đã chốt ở trên.
nonisolated struct P2: Equatable {
    var x: Double
    var y: Double

    static func + (l: P2, r: P2) -> P2 { P2(x: l.x + r.x, y: l.y + r.y) }
    static func - (l: P2, r: P2) -> P2 { P2(x: l.x - r.x, y: l.y - r.y) }
    static func / (l: P2, k: Double) -> P2 { P2(x: l.x / k, y: l.y / k) }
}

/// Một điểm trong không gian thật, đơn vị MÉT, gốc = trung điểm hai hông.
nonisolated struct P3: Equatable {
    var x: Double
    var y: Double
    var z: Double
}

/// Tên 33 điểm MediaPipe trả về, đặt theo chỉ số của thư viện.
///
/// ⚠️ Tên đặt theo GIẢI PHẪU của người mẫu, KHÔNG theo phía màn hình. Mẫu quay
/// mặt vào máy thì `LEFT_SHOULDER` nằm ở bên PHẢI ảnh. Đảo thứ tự x của cặp vai
/// chính là phép phân biệt đang thấy mặt trước hay thấy lưng.
nonisolated enum Lm {
    static let nose = 0
    static let leftEyeInner = 1
    static let leftEye = 2
    static let leftEyeOuter = 3
    static let rightEyeInner = 4
    static let rightEye = 5
    static let rightEyeOuter = 6
    static let leftEar = 7
    static let rightEar = 8
    static let mouthLeft = 9
    static let mouthRight = 10
    static let leftShoulder = 11
    static let rightShoulder = 12
    static let leftElbow = 13
    static let rightElbow = 14
    static let leftWrist = 15
    static let rightWrist = 16
    static let leftPinky = 17
    static let rightPinky = 18
    static let leftIndex = 19
    static let rightIndex = 20
    static let leftThumb = 21
    static let rightThumb = 22
    static let leftHip = 23
    static let rightHip = 24
    static let leftKnee = 25
    static let rightKnee = 26
    static let leftAnkle = 27
    static let rightAnkle = 28
    static let leftHeel = 29
    static let rightHeel = 30
    static let leftFootIndex = 31
    static let rightFootIndex = 32

    static let count = 33

    /// Chỉ số khớp ĐỐI XỨNG qua trục dọc cơ thể. Dùng khi lật ảnh gương.
    ///
    /// Danh sách của MediaPipe xếp thành từng cặp trái-phải liền nhau: mũi đứng một
    /// mình ở 0, rồi 1↔4, 2↔5, 3↔6 (ba điểm quanh mắt), 7↔8 (tai), 9↔10 (khoé
    /// miệng), và từ 11 trở đi là các cặp lẻ-chẵn liền kề.
    static func mirrorIndex(_ i: Int) -> Int {
        switch i {
        case nose: return nose
        case leftEyeInner...leftEyeOuter: return i + 3
        case rightEyeInner...rightEyeOuter: return i - 3
        case leftEar...rightFootIndex: return i % 2 == 1 ? i + 1 : i - 1
        default: return i
        }
    }

    /// Các cặp điểm nối thành xương, dùng để vẽ khung xương lên màn hình.
    static let bones: [(Int, Int)] = [
        // Thân
        (leftShoulder, rightShoulder),
        (leftShoulder, leftHip),
        (rightShoulder, rightHip),
        (leftHip, rightHip),
        // Tay
        (leftShoulder, leftElbow), (leftElbow, leftWrist),
        (rightShoulder, rightElbow), (rightElbow, rightWrist),
        // Chân
        (leftHip, leftKnee), (leftKnee, leftAnkle), (leftAnkle, leftHeel),
        (leftHeel, leftFootIndex),
        (rightHip, rightKnee), (rightKnee, rightAnkle), (rightAnkle, rightHeel),
        (rightHeel, rightFootIndex),
        // Mặt
        (nose, leftEye), (leftEye, leftEar),
        (nose, rightEye), (rightEye, rightEar),
        (mouthLeft, mouthRight),
    ]
}

/// Một khung hình đã được đo. Đây là thứ DUY NHẤT các tầng trên được phép dùng —
/// không tầng nào được chạm thẳng vào kiểu dữ liệu của MediaPipe.
nonisolated struct PoseFrame {
    /// 33 điểm trên khung hình, theo quy ước đã chốt (y hướng XUỐNG).
    var points: [P2]
    /// Độ tin cậy từng điểm, 0..1. Điểm nằm ngoài khung vẫn được trả về nhưng tin cậy thấp.
    var visibility: [Float]
    /// 33 điểm trong không gian thật (mét), gốc = trung điểm hai hông. Rỗng nếu không có.
    var world: [P3]
    /// Thời điểm khung hình được chụp, mili-giây.
    var timestampMs: Int64

    init(points: [P2], visibility: [Float], world: [P3], timestampMs: Int64) {
        self.points = points
        self.visibility = visibility
        self.world = world
        self.timestampMs = timestampMs
    }

    var isEmpty: Bool { points.isEmpty }

    /// Lấy điểm nếu độ tin cậy đủ cao VÀ toạ độ còn nằm trong khung, ngược lại trả nil.
    func at(_ index: Int, minVisibility: Float) -> P2? {
        guard index >= 0, index < points.count, index < visibility.count else { return nil }
        guard visibility[index] >= minVisibility else { return nil }
        let p = points[index]
        // Bẫy tài liệu §3.3 cảnh báo: MediaPipe vẫn trả về điểm NGOÀI khung bằng
        // ngoại suy. Chỉ kiểm độ tin cậy là chưa đủ - phải kiểm cả toạ độ, nếu
        // không ảnh chân dung sẽ bị nhận nhầm thành ảnh toàn thân.
        if p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 { return nil }
        return p
    }

    /// LẬT NGANG khung xương — dùng cho ẢNH CHỤP QUA GƯƠNG.
    ///
    /// ## Vì sao cần
    ///
    /// Ảnh gương là ảnh của một người **bị lật ngang**. Bộ nhận diện đặt tên khớp
    /// theo GIẢI PHẪU, nên với ảnh gương nó gọi tay PHẢI thật của người đó là
    /// `leftWrist`. Hệ quả: câu nhắc *"đưa tay trái lên cao"* làm người ta giơ tay
    /// trái thật, nhưng số đo lại đọc ở tay kia → **lời nhắc không bao giờ tắt**.
    ///
    /// Hàm này đưa mọi thứ về **không gian chuẩn** — cảnh sẽ trông thế nào nếu
    /// không có gương. Ảnh mẫu và khung camera mỗi bên tự quy về đó, rồi mới so.
    ///
    /// ## Ba việc phải làm cùng lúc
    ///
    /// 1. Toạ độ ảnh: `x → 1 - x`
    /// 2. Toạ độ thật: `x → -x`
    /// 3. **Hoán đổi nhãn TRÁI ↔ PHẢI của mọi khớp**
    ///
    /// Thiếu bước 3 là hỏng nặng nhất mà không có gì báo: hình lật đúng nhưng vai
    /// trái vẫn mang tên vai trái, nên góc xoay thân đảo dấu và mọi câu về tay chân
    /// chỉ nhầm bên.
    ///
    /// ⚠️ **Việc lật này làm ĐẢO CHIỀU hai câu nhắc**: *lệch trái/phải* và *nghiêng
    /// ngang*. Trong không gian chuẩn, dịch máy sang phải làm chủ thể chạy sang
    /// PHẢI, ngược với camera thường. Xem `CuePresenter`.
    func mirrored() -> PoseFrame {
        guard !isEmpty else { return self }
        var p = Array(repeating: P2(x: 0, y: 0), count: points.count)
        var v = Array(repeating: Float(0), count: visibility.count)
        var w = Array(repeating: P3(x: 0, y: 0, z: 0), count: world.count)
        for i in points.indices {
            let j = Lm.mirrorIndex(i)
            guard j >= 0, j < p.count else { continue }
            p[j] = P2(x: 1.0 - points[i].x, y: points[i].y)
            if i < v.count { v[j] = visibility[i] }
            if i < w.count { w[j] = P3(x: -world[i].x, y: world[i].y, z: world[i].z) }
        }
        return PoseFrame(points: p, visibility: v, world: w, timestampMs: timestampMs)
    }

    /// CẮT KHUNG VỀ ĐÚNG TỈ LỆ CỦA ẢNH MẪU, rồi quy toạ độ theo khung đã cắt.
    ///
    /// ## Vì sao bắt buộc
    ///
    /// Toạ độ khớp là **tỉ lệ so với khung hình chứa nó** — `x = 0,5` nghĩa là "giữa
    /// khung", không phải một vị trí trong thế giới thật. Nên cùng một người đứng
    /// cùng một chỗ, chụp bằng khung 4:3 và khung 9:16 sẽ ra **hai bộ số khác nhau**.
    ///
    /// Ảnh mẫu có tỉ lệ của nó; camera có tỉ lệ của cảm biến. Không đưa về chung một
    /// tỉ lệ thì mục *lệch trái/phải* và *máy cao/thấp* đang so hai thứ không so được,
    /// và người dùng thấy **chủ thể luôn lệch một chút mà chỉnh mãi không khớp**.
    ///
    /// PO đã chốt từ đầu: *"template vuông thì khung vuông, template 9:16 thì khung
    /// camera 9:16"*.
    ///
    /// ## Cách làm
    ///
    /// Cắt phần GIỮA khung sao cho tỉ lệ còn lại đúng bằng `targetAspect`, rồi quy
    /// toạ độ về khung mới. Điểm rơi ra ngoài phần cắt sẽ có toạ độ ngoài `0..1` và
    /// bị `at` loại — đúng như khi nó nằm ngoài khung ảnh thật.
    ///
    /// Toạ độ THẬT (`world`) không đụng tới: nó tính bằng mét, không phụ thuộc khung.
    ///
    /// - Parameter targetAspect: tỉ lệ ngang/dọc của ẢNH MẪU
    /// - Parameter frameAspect: tỉ lệ ngang/dọc của KHUNG HÌNH hiện tại
    func croppedToAspect(targetAspect: Double, frameAspect: Double) -> PoseFrame {
        guard !isEmpty else { return self }
        if targetAspect <= 0 || frameAspect <= 0 { return self }
        // Lệch dưới 1% thì cắt cũng như không — bỏ qua cho đỡ tính thừa.
        if abs(targetAspect - frameAspect) / frameAspect < 0.01 { return self }

        var pts: [P2] = []
        pts.reserveCapacity(points.count)
        if targetAspect < frameAspect {
            // Ảnh mẫu HẸP hơn khung → cắt hai bên.
            let f = targetAspect / frameAspect
            let edge = (1.0 - f) / 2.0
            for p in points { pts.append(P2(x: (p.x - edge) / f, y: p.y)) }
        } else {
            // Ảnh mẫu RỘNG hơn khung → cắt trên dưới.
            let f = frameAspect / targetAspect
            let edge = (1.0 - f) / 2.0
            for p in points { pts.append(P2(x: p.x, y: (p.y - edge) / f)) }
        }
        return PoseFrame(points: pts, visibility: visibility, world: world, timestampMs: timestampMs)
    }

    func world(_ index: Int, minVisibility: Float) -> P3? {
        guard index >= 0, index < world.count, index < visibility.count else { return nil }
        guard visibility[index] >= minVisibility else { return nil }
        return world[index]
    }

    /// Điểm CỔ — MediaPipe không có sẵn, phải suy ra (FOOTGUNS.md mục 4).
    /// Vision của iOS có `neck` sẵn; công thức trung điểm hai vai là đúng thứ bản
    /// Swift vẫn dùng, nên tương thích.
    func neck(minVisibility: Float) -> P2? {
        guard let l = at(Lm.leftShoulder, minVisibility: minVisibility) else { return nil }
        guard let r = at(Lm.rightShoulder, minVisibility: minVisibility) else { return nil }
        return (l + r) / 2.0
    }

    /// Điểm GỐC THÂN (giữa hai hông) — cũng phải suy ra, cùng lý do như `neck`.
    func root(minVisibility: Float) -> P2? {
        guard let l = at(Lm.leftHip, minVisibility: minVisibility) else { return nil }
        guard let r = at(Lm.rightHip, minVisibility: minVisibility) else { return nil }
        return (l + r) / 2.0
    }

    /// Góc xoay thân quanh trục đứng, ĐỘ. 0 = mẫu quay thẳng mặt vào máy.
    ///
    /// Dùng toạ độ 3 chiều thật nên `atan2` ổn định ở MỌI góc — không có điểm kỳ
    /// dị. Bản cũ phải suy gián tiếp từ tỉ lệ vai/thân rồi `acos`, mà đạo hàm
    /// `acos` tiến tới vô cùng ở gần chính diện: nhiễu đầu vào 2% biến thành nhiễu
    /// góc hơn 10°, buộc phải thêm vùng chết và bộ lọc bù. Ở đây bỏ được hết.
    ///
    /// ⚠️ CHƯA KIỂM CHỨNG TRÊN MÁY THẬT. `world` là kết quả model ƯỚC LƯỢNG, không
    /// phải đo đạc. Đây chính là con số #4 trong buổi đo bắt buộc (TONG_QUAN §10.3).
    func bodyYawDeg(minVisibility: Float) -> Double? {
        guard let l = world(Lm.leftShoulder, minVisibility: minVisibility) else { return nil }
        guard let r = world(Lm.rightShoulder, minVisibility: minVisibility) else { return nil }

        // THỨ TỰ HAI VAI QUYẾT ĐỊNH GỐC 0°. Đảo thứ tự là lệch đúng 180°.
        //
        // Tài liệu quy định: 0° = mẫu quay thẳng mặt vào máy, ±180° = quay lưng.
        //
        // Mẫu nhìn thẳng vào máy thì vai-TRÁI-giải-phẫu nằm ở bên PHẢI ảnh
        // (x lớn hơn), hai vai cùng độ sâu z. Vậy:
        //     atan2(l.z − r.z, l.x − r.x) = atan2(0, số dương) = 0°  ✅
        // Viết ngược lại thành (r − l) sẽ ra atan2(0, số âm) = 180° — tức mẫu
        // nhìn thẳng vào máy mà máy báo "đang quay lưng".
        //
        // ĐÃ KIỂM THỰC TẾ trên ảnh mẫu của dự án: người đứng nghiêng ~35°, công
        // thức cũ báo 144,8°, công thức này báo −35,2° — khớp với mắt nhìn.
        //
        // ⚠️ CÒN PHẢI KIỂM DẤU trái/phải trên máy thật (buổi đo §10.3, con số #4):
        // gốc 0° đã đúng, nhưng nghiêng sang trái ra số âm hay dương thì chưa xác nhận.
        return atan2(l.z - r.z, l.x - r.x) * 180.0 / Double.pi
    }

    /// Bề rộng vai biểu kiến trên khung hình — dùng để theo dõi độ ổn định phép đo.
    func shoulderSpanNormalized(minVisibility: Float) -> Double? {
        guard let l = at(Lm.leftShoulder, minVisibility: minVisibility) else { return nil }
        guard let r = at(Lm.rightShoulder, minVisibility: minVisibility) else { return nil }
        return hypot(r.x - l.x, r.y - l.y)
    }

    /// Chiều cao mẫu ước lượng theo MÉT, suy từ toạ độ thật.
    /// Đây là con số #5 trong buổi đo — nếu khớp chiều cao thật thì bỏ được giả
    /// định "mẫu cao 1m70" mà bản cũ buộc phải dùng.
    func bodyHeightMeters(minVisibility: Float) -> Double? {
        guard let nose = world(Lm.nose, minVisibility: minVisibility) else { return nil }
        let la = world(Lm.leftAnkle, minVisibility: minVisibility)
        let ra = world(Lm.rightAnkle, minVisibility: minVisibility)
        // `max` của y = điểm cao nhất (y hướng xuống), đúng như `.maxOrNull()` bên Kotlin.
        guard let ankleY = [la?.y, ra?.y].compactMap({ $0 }).max() else { return nil }
        // Gốc toạ độ ở hông; y hướng xuống. Bù thêm phần đỉnh đầu phía trên mũi.
        return (ankleY - nose.y) * 1.08
    }

    /// Khung bao chủ thể (chỉ tính điểm còn trong khung), dùng để suy lớp khung hình.
    func subjectBox(minVisibility: Float) -> Box? {
        var minX = Double.infinity
        var maxX = -Double.infinity
        var minY = Double.infinity
        var maxY = -Double.infinity
        var found = false
        for i in points.indices {
            guard let p = at(i, minVisibility: minVisibility) else { continue }
            found = true
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        return found ? Box(left: minX, top: minY, right: maxX, bottom: maxY) : nil
    }

    static let empty = PoseFrame(points: [], visibility: [], world: [], timestampMs: 0)
}

/// Khung bao, theo quy ước toạ độ đã chốt (y hướng xuống).
nonisolated struct Box: Equatable {
    var left: Double
    var top: Double
    var right: Double
    var bottom: Double

    var width: Double { right - left }
    var height: Double { bottom - top }
}
