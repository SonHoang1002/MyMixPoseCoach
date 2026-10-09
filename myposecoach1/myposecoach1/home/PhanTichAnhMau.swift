import Foundation
import UIKit

/// Kết quả phân tích MỘT LẦN một ảnh mẫu — dùng chung cho cổng kiểm, hồ sơ tiêu chí
/// và bảng gắn nhãn ảnh tự nhập, để không phân tích lại và chắc chắn các bên nói về
/// cùng một kết quả.
///
/// Bản port từ `home/PhanTichAnhMau.kt` của Android. Khác một chỗ: **bản iOS chưa
/// có bộ nhận diện khuôn mặt** (`FaceAnalyzer` của Android dùng ML Kit; iOS chỉ có
/// struct `FaceInfo` rỗng). Nên `face` luôn là `nil` — mục "Mắt mở" và các mốc đo
/// dựa vào mặt sẽ do `TemplateProfile.from` tự bỏ qua và ghi lý do, đúng luật
/// "mục không đo được thì bỏ ra, không trừ điểm".
nonisolated struct PhanTichAnhMau {
    let verdict: TemplateVerdict
    let frame: PoseFrame?
    let face: FaceInfo?
    let poseGuide: [String]
    let difficulty: PoseDescriber.Difficulty?

    var framing: FramingClass? {
        if case .Accepted(let f, _) = verdict { return f }
        return nil
    }

    /// Hồ sơ tiêu chí; [gocMayNhan] là nhãn góc máy nếu có. `nil` khi ảnh bị từ chối.
    func hoSo(
        gocMayNhan: Double?,
        kieuChupTren: KieuChupTren? = nil
    ) -> TemplateProfile? {
        guard let f = frame, let k = framing else { return nil }
        return TemplateProfile.from(
            f, framing: k, minVisibility: TemplateGate.CORE_VIS, face: face,
            gocMayNhan: gocMayNhan, kieuChupTren: kieuChupTren
        )
    }
}

/// Chạy chặn luồng nền — KHÔNG gọi từ luồng giao diện (MediaPipe 9MB + giải mã ảnh).
nonisolated func phanTichAnhMau(file: URL) -> PhanTichAnhMau {
    let bmp = UprightBitmap.decode(file: file)
    let frame: PoseFrame? = bmp.flatMap { StillPoseAnalyzer.analyze(image: $0) }
    let v = TemplateGate.check(frame)

    // Nhận diện mặt CHỈ chạy khi ảnh đã qua cổng kiểm — ảnh bị từ chối thì chẳng
    // dùng tới, chạy chỉ tốn thời gian chờ. Bản iOS chưa có FaceAnalyzer nên face
    // luôn nil (xem chú thích [PhanTichAnhMau]).
    let face: FaceInfo? = nil
    let accepted: Bool = {
        if case .Accepted = v { return true }
        return false
    }()

    let guide: [String]
    let diff: PoseDescriber.Difficulty?
    if let f = frame, accepted, case .Accepted(let framing, _) = v {
        guide = PoseDescriber.describe(f, minVis: TemplateGate.CORE_VIS)
        diff = PoseDescriber.difficulty(f, framing: framing, minVis: TemplateGate.CORE_VIS)
    } else {
        guide = []
        diff = nil
    }

    return PhanTichAnhMau(
        verdict: v,
        frame: frame,
        face: face,
        poseGuide: guide,
        difficulty: diff
    )
}
