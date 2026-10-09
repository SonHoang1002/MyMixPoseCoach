import CoreVideo
import Foundation
import ImageIO
import UIKit
import Vision

// Bộ nhận diện khung xương bằng Apple Vision — THAY THẾ MediaPipe.
//
// ## Vì sao đổi
//
// MediaPipeTasksVision 1.0.0 dựng pipeline Metal riêng cả khi `delegate = .CPU`,
// và trên iOS 27 chạm vào selector `AGXA13FamilyFunctionHandle resourceIndex` mà
// driver AGX không còn trả lời — app sập ngay lúc khởi tạo `PoseLandmarker`.
// Vision là framework của hệ điều hành, không có pipeline Metal riêng, nên hết
// hẳn lớp lỗi đó.
//
// ## Hệ toạ độ
//
// Vision trả toạ độ chuẩn hoá 0-1, gốc ở góc DƯỚI-trái, y hướng LÊN. Quy ước của
// toàn app (PoseGeometry) là gốc TRÊN-trái, y hướng XUỐNG — nên ở đây đổi
// `y → 1 - y` MỘT LẦN DUY NHẤT. Không nơi nào khác được lật y.
//
// Vision xoay ảnh theo `orientation` ta truyền trước khi suy khớp, nên khớp trả
// về nằm trong hệ của ảnh ĐÃ DỰNG ĐÚNG CHIỀU.
//
// ## Nhãn trái/phải
//
// ⚠️ CẦN KIỂM CHỨNG TRÊN MÁY THẬT. Vision đặt tên khớp theo cơ thể người mẫu,
// cùng quy ước với ML Kit/MediaPipe mà app vốn dùng (`PoseDescriber` dựa vào điều
// này). Nếu khi đo thực tế thấy TRÁI/PHẢI bị đảo (giơ tay trái mà app báo tay
// phải), chỉ cần đổi cặp chỉ số trong hai hàm `put` bên dưới — xem `Lm.mirrorIndex`.
//
// ## Số khớp
//
// Vision cho 19 khớp 2D (thiếu ngón tay, gót, mũi chân, khoé miệng). App chỉ dùng
// tới cổ tay/cổ chân, nên khớp thiếu để độ tin cậy 0 → mọi phép đọc `at()` tự bỏ
// qua, khung xương vẫn vẽ đúng. Mảng luôn đủ 33 phần tử để khớp `Lm.count`.
nonisolated enum VisionPose {

    /// Chạy thêm request 3D để lấy `world` (mét). Tắt được nếu cần tăng tốc.
    static var include3D = true

    // MARK: - Đầu vào

    static func frame(fromPixelBuffer pixelBuffer: CVPixelBuffer,
                      orientation: CGImagePropertyOrientation) -> PoseFrame? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])
        return run(handler: handler)
    }

    static func frame(fromCGImage image: CGImage,
                      orientation: CGImagePropertyOrientation) -> PoseFrame? {
        let handler = VNImageRequestHandler(cgImage: image,
                                            orientation: orientation,
                                            options: [:])
        return run(handler: handler)
    }

    // MARK: - Ánh xạ hướng

    /// Góc CameraX (`imageInfo.rotationDegrees`, xoay THUẬN chiều kim đồng hồ để
    /// ảnh dựng đúng) → hướng EXIF của Vision.
    static func cgOrientation(fromDegrees degrees: Int) -> CGImagePropertyOrientation {
        switch ((degrees % 360) + 360) % 360 {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    // MARK: - Chạy

    private static func run(handler: VNImageRequestHandler) -> PoseFrame? {
        let pose2D = VNDetectHumanBodyPoseRequest()
        var requests: [VNRequest] = [pose2D]
        let pose3D: VNDetectHumanBodyPose3DRequest? = include3D ? VNDetectHumanBodyPose3DRequest() : nil
        if let pose3D { requests.append(pose3D) }

        do {
            try handler.perform(requests)
        } catch {
            NSLog("VisionPose: request thất bại — \(error)")
            return nil
        }

        // Không thấy người: trả khung RỖNG (khác `nil` = không chạy được). Bên gọi
        // phân biệt hai tình huống này để báo đúng nguyên nhân.
        guard let obs = pose2D.results?.first as? VNHumanBodyPoseObservation,
              let recognized = try? obs.recognizedPoints(.all) else {
            return PoseFrame(points: [], visibility: [], world: [], timestampMs: 0)
        }

        var points = [P2](repeating: P2(x: 0, y: 0), count: Lm.count)
        var visibility = [Float](repeating: 0, count: Lm.count)

        func put(_ index: Int, _ joint: VNHumanBodyPoseObservation.JointName) {
            guard let p = recognized[joint], p.confidence > 0 else { return }
            // Vision: gốc dưới-trái, y LÊN → app: gốc trên-trái, y XUỐNG.
            points[index] = P2(x: Double(p.location.x), y: 1.0 - Double(p.location.y))
            visibility[index] = Float(p.confidence)
        }

        // Đầu
        put(Lm.nose, .nose)
        put(Lm.leftEye, .leftEye)
        put(Lm.leftEyeInner, .leftEye)
        put(Lm.leftEyeOuter, .leftEye)
        put(Lm.rightEye, .rightEye)
        put(Lm.rightEyeInner, .rightEye)
        put(Lm.rightEyeOuter, .rightEye)
        put(Lm.leftEar, .leftEar)
        put(Lm.rightEar, .rightEar)
        // Thân trên
        put(Lm.leftShoulder, .leftShoulder)
        put(Lm.rightShoulder, .rightShoulder)
        put(Lm.leftElbow, .leftElbow)
        put(Lm.rightElbow, .rightElbow)
        put(Lm.leftWrist, .leftWrist)
        put(Lm.rightWrist, .rightWrist)
        // Thân dưới
        put(Lm.leftHip, .leftHip)
        put(Lm.rightHip, .rightHip)
        put(Lm.leftKnee, .leftKnee)
        put(Lm.rightKnee, .rightKnee)
        put(Lm.leftAnkle, .leftAnkle)
        put(Lm.rightAnkle, .rightAnkle)

        var world: [P3] = []
        if let obs3 = pose3D?.results?.first as? VNHumanBodyPose3DObservation {
            world = worldLandmarks(obs3)
        }

        return PoseFrame(points: points, visibility: visibility, world: world, timestampMs: 0)
    }

    // MARK: - Khớp 3D (mét)

    /// Khớp 3D của Vision: 17 điểm, đơn vị MÉT, gốc ở `root` (giữa hai hông) —
    /// đúng quy ước `P3`. `position` là ma trận 4×4 kiểu ARKit; cột thứ 4 là tịnh tiến.
    ///
    /// ⚠️ CẦN KIỂM CHỨNG hệ trục trên máy thật (cùng buổi đo với `bodyYawDeg`).
    /// Quy ước app: y hướng XUỐNG — nên đảo dấu y của Vision (ARKit y hướng LÊN).
    /// Dấu của `z` (chiều sâu) giữ nguyên, chưa xác nhận.
    private static func worldLandmarks(_ obs: VNHumanBodyPose3DObservation) -> [P3] {
        var world = [P3](repeating: P3(x: 0, y: 0, z: 0), count: Lm.count)

        func put(_ index: Int, _ joint: VNHumanBodyPose3DObservation.JointName) {
            guard let p = try? obs.recognizedPoint(joint) else { return }
            let t = p.position.columns.3
            world[index] = P3(x: Double(t.x), y: -Double(t.y), z: Double(t.z))
        }

        // Vision 3D không có `nose`: dùng `centerHead` (gần đúng cho mũi/đo cao).
        put(Lm.nose, .centerHead)
        put(Lm.leftShoulder, .leftShoulder)
        put(Lm.rightShoulder, .rightShoulder)
        put(Lm.leftElbow, .leftElbow)
        put(Lm.rightElbow, .rightElbow)
        put(Lm.leftWrist, .leftWrist)
        put(Lm.rightWrist, .rightWrist)
        put(Lm.leftHip, .leftHip)
        put(Lm.rightHip, .rightHip)
        put(Lm.leftKnee, .leftKnee)
        put(Lm.rightKnee, .rightKnee)
        put(Lm.leftAnkle, .leftAnkle)
        put(Lm.rightAnkle, .rightAnkle)
        return world
    }
}

nonisolated extension CGImagePropertyOrientation {
    /// UIImage.Orientation và CGImagePropertyOrientation mô tả cùng một hướng theo
    /// hai thang EXIF khác gốc, và trùng tên-theo-tên (đã đối chiếu giá trị thô).
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

nonisolated extension UIImage.Orientation {
    /// Chiều ngược lại của ánh xạ trên.
    init(_ orientation: CGImagePropertyOrientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
