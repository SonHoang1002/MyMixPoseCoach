import Foundation

/// LỚP KHUNG HÌNH — khái niệm hạng nhất của dự án.
///
/// Suy **MỘT LẦN** từ ảnh mẫu, rồi áp **NGUYÊN XI** cho mọi khung hình camera và
/// mọi khung hình video sau đó. **Không bao giờ để camera live tự chọn mốc đo.**
///
/// Đây là chỗ sửa "nguyên nhân thứ 8" — lỗi duy nhất khiến hướng dẫn KHÔNG BAO GIỜ
/// tắt được: ảnh mẫu chân dung đo bằng "đỉnh đầu → hông", còn camera thấy toàn thân
/// nên tự chọn "đỉnh đầu → cổ chân". Hai đại lượng khác bản chất, phép trừ giữa
/// chúng vô nghĩa. Không ngưỡng nào cứu được, vì vấn đề không nằm ở ngưỡng.
nonisolated enum FramingClass: String, CaseIterable, Hashable {
    case full = "Toàn thân"
    case knee = "3/4 người"
    case half = "Nửa người"
    case chest = "Bán thân"
    case head = "Chân dung cận"

    var displayName: String { rawValue }

    /// Lớp này có thấy chân không.
    ///
    /// ⚠️ Quyết định KIỂM ZOOM ĐƯỢC HAY KHÔNG nằm ở đây. Phép đo độ méo phối cảnh
    /// dựa vào chân — bộ phận lệch xa tầm máy nhất nên co ngắn mạnh nhất khi đứng
    /// gần. Không thấy chân thì chỉ còn cái đầu để đo, mà đầu xoay tự do nên chỉ số
    /// bám theo tư thế đầu chứ không theo khoảng cách máy (đã đo, FOOTGUNS 37).
    ///
    /// Quyết định sản phẩm 04/09/2026: **ảnh chân dung KHÔNG kiểm zoom**, thay vào
    /// đó dựa vào mục xa/gần cộng với việc khoá zoom về 1x ở màn camera.
    var seesLegs: Bool { self == .full || self == .knee }

    /// Mốc đo tỉ lệ chủ thể trong khung (mục 2 — xa/gần).
    var scaleAnchor: ScaleAnchor {
        switch self {
        case .full: return .headToAnkle
        case .knee: return .headToKnee
        case .half: return .headToHip
        case .chest, .head: return .faceHeight
        }
    }

    /// Điểm mốc đo GÓC NHÌN của máy (mục 3 — máy cao/thấp).
    ///
    /// ⚠️ Mốc này KHÔNG phải phép đo — nó là một số hạng trong công thức góc:
    ///
    ///     elevation = độ_nghiêng_máy + (0,5 − y_mốc) × vFOV
    ///
    /// Bản trước đây lấy thẳng `y_mốc` làm phép đo và gọi đó là "máy cao/thấp".
    /// Sai: `y` là BỐ CỤC, thiếu hai số hạng kia thì nó nhạy với khoảng cách hơn
    /// cả với độ cao máy (đo 12/09/2026: 0,058 so với 0,041). Xem FOOTGUNS 62.
    ///
    /// Nhưng vứt luôn cái mốc đi cũng sai — `y` là một nửa của phương trình.
    var elevationAnchor: ElevationAnchor {
        switch self {
        case .full, .knee: return .midHip
        case .half: return .midTorso
        case .chest, .head: return .eyeLine
        }
    }

    /// Điểm mốc đo lệch trái/phải (mục 5).
    var centerAnchor: CenterAnchor {
        switch self {
        case .full, .knee, .half: return .torsoCenter
        case .chest: return .shoulderCenter
        case .head: return .faceCenter
        }
    }

    /// Nguồn đo hướng mẫu (mục 1).
    ///
    /// Chân dung/bán thân thường không thấy hông. Đổi lại, góc mặt chính xác hơn hẳn
    /// (~3-5° so với 8-10°) — nên **chân dung đo hướng CHÍNH XÁC HƠN toàn thân**,
    /// không phải kém hơn.
    var yawSource: YawSource {
        switch self {
        case .full, .knee, .half: return .body3D
        case .chest, .head: return .faceYaw
        }
    }

    /// Nhóm khớp được chấm ở mục 6 — chỉ chấm nhóm còn nằm trong khung.
    var poseGroups: Set<PoseGroup> {
        switch self {
        case .full: return [.spine, .head, .arms, .legs]
        case .knee, .half: return [.spine, .head, .arms]
        case .chest: return [.head, .arms]
        case .head: return [.head]
        }
    }

    /// Suy lớp khung hình từ một khung hình đã đo.
    ///
    /// ⚠️ PHẢI KIỂM CẢ HAI ĐIỀU KIỆN: **thấy khớp nào** VÀ **đáy khung bao ở đâu**.
    ///
    /// Bản iOS cũ (`FramingClass.swift`) chỉ kiểm đáy khung bao, bỏ mất điều kiện
    /// khớp — và điều đó **sai thật**, đã kiểm chứng trên chính ảnh mẫu của dự án:
    /// ảnh nửa người (chân cắt ngang đùi) có đáy 0,90, lọt vào dải 0,80–0,97 nên
    /// bản iOS cũ kết luận là "toàn thân". Sai lớp = sai toàn bộ mốc đo.
    ///
    /// Bẫy kèm theo: bộ nhận diện vẫn trả về điểm NGOÀI khung bằng ngoại suy với
    /// độ tin cậy thấp. `PoseFrame.at` đã lọc cả độ tin cậy lẫn toạ độ, nên ở đây
    /// chỉ cần hỏi "có điểm không".
    static func detect(_ frame: PoseFrame, minVisibility: Float) -> FramingClass? {
        guard let box = frame.subjectBox(minVisibility: minVisibility) else { return nil }
        let bottom = box.bottom

        func seesAny(_ idx: Int...) -> Bool {
            idx.contains { frame.at($0, minVisibility: minVisibility) != nil }
        }

        let seesAnkle = seesAny(Lm.leftAnkle, Lm.rightAnkle)
        let seesKnee = seesAny(Lm.leftKnee, Lm.rightKnee)
        let seesHip = seesAny(Lm.leftHip, Lm.rightHip)

        // Đáy sát mép dưới => phần dưới cơ thể đã bị cắt, con số đáy không tin được.
        let cutAtBottom = bottom > 0.97

        // ⚠️ MỐC NHÌN THẤY THẮNG NGƯỠNG CHIỀU CAO.
        //
        // Hai ngưỡng 0,80 và 0,72 dưới đây viết theo NGƯỜI ĐỨNG — người đứng thì
        // chân luôn kéo dài xuống gần đáy khung. Người NGỒI thì thấp hơn hẳn:
        // một ảnh mẫu người ngồi giữa khung, thấy rõ cả bàn chân, thân chỉ chạm
        // 65% chiều cao ảnh — sẽ bị xếp nhầm vào HALF và **mất tiêu chí zoom dù
        // chân hiện rõ mồn một**. Đúng kiểu thất bại im lặng mà quy tắc số 7 cấm.
        //
        // Nên: mốc đã NHÌN THẤY được thì tin thẳng vào nó. Ngưỡng chiều cao chỉ
        // còn dùng để SUY ĐOÁN khi mốc bị che.
        if seesAnkle && !cutAtBottom { return .full }
        if seesKnee && !cutAtBottom { return .knee }
        if seesAnkle && bottom > 0.80 { return .full }
        if seesKnee && bottom > 0.72 { return .knee }
        if seesHip && bottom > 0.55 { return .half }
        if box.height > 0.30 { return .chest }
        return .head
    }
}

nonisolated enum ScaleAnchor: Hashable {
    case headToAnkle, headToKnee, headToHip, faceHeight
}

/// Điểm mốc tính góc nhìn của máy. Nhãn dùng cho câu giải thích khi bỏ mục.
nonisolated enum ElevationAnchor: String, Hashable {
    case midHip = "ngang hông mẫu"
    case midTorso = "ngang thân mẫu"
    case eyeLine = "ngang mắt mẫu"

    var cueLabel: String { rawValue }
}

nonisolated enum CenterAnchor: Hashable {
    case torsoCenter, shoulderCenter, faceCenter
}

nonisolated enum YawSource: Hashable {
    case body3D, faceYaw
}

nonisolated enum PoseGroup: CaseIterable, Hashable {
    case spine, head, arms, legs
}
