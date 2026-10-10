import Foundation
import MediaPipeTasksVision
import UIKit

/// Cầu nối DUY NHẤT từ MediaPipe sang kiểu dữ liệu thuần `PoseFrame` của app.
/// Cả ảnh mẫu, video và camera phải dùng cùng model, cùng ngưỡng và hàm chuyển đổi này.
nonisolated enum MediaPipePose {
    private static let creationLock = NSLock()
    private static let crashMarker = "pose.mediapipe.initializing"

    enum EngineError: LocalizedError {
        case previousNativeCrash
        case missingModel(String)

        var errorDescription: String? {
            switch self {
            case .previousNativeCrash:
                return "MediaPipe đã sập ở lần khởi tạo trước; tạm dùng Apple Vision để app vẫn mở được."
            case .missingModel(let name):
                return "Không tìm thấy model pose trong bundle: \(name)"
            }
        }
    }

    /// Dấu này được ghi ra đĩa TRƯỚC lệnh native. Nếu tiến trình chết trong C++/Metal,
    /// lần mở sau sẽ không lặp vô hạn crash-loop. Xoá app hoặc đặt lại key để thử lại.
    static var wasQuarantinedAfterNativeCrash: Bool {
        UserDefaults.standard.bool(forKey: crashMarker)
    }

    static func makeLandmarker(
        mode: RunningMode,
        modelAsset: String,
        minDetection: Float = 0.5,
        minPresence: Float = 0.5,
        minTracking: Float = 0.5
    ) throws -> PoseLandmarker {
        creationLock.lock()
        defer { creationLock.unlock() }

        guard !wasQuarantinedAfterNativeCrash else {
            throw EngineError.previousNativeCrash
        }
        let path = PoseDetector.modelAssetPath(for: modelAsset)
        guard FileManager.default.fileExists(atPath: path) else {
            throw EngineError.missingModel(modelAsset)
        }

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: crashMarker)
        defaults.synchronize()
        do {
            let options = PoseLandmarkerOptions()
            options.baseOptions.modelAssetPath = path
            options.baseOptions.delegate = .CPU
            options.runningMode = mode
            options.numPoses = 1
            options.minPoseDetectionConfidence = minDetection
            options.minPosePresenceConfidence = minPresence
            options.minTrackingConfidence = minTracking
            options.shouldOutputSegmentationMasks = false
            let result = try PoseLandmarker(options: options)
            defaults.removeObject(forKey: crashMarker)
            defaults.synchronize()
            return result
        } catch {
            // Lỗi Swift/Objective-C đã bắt được không phải native crash; cho phép thử lại.
            defaults.removeObject(forKey: crashMarker)
            defaults.synchronize()
            throw error
        }
    }

    static func image(_ image: UIImage) throws -> MPImage {
        try MPImage(uiImage: image)
    }

    static func image(_ pixelBuffer: CVPixelBuffer, rotationDegrees: Int) throws -> MPImage {
        try MPImage(pixelBuffer: pixelBuffer, orientation: orientation(fromDegrees: rotationDegrees))
    }

    static func orientation(fromDegrees degrees: Int) -> UIImage.Orientation {
        switch ((degrees % 360) + 360) % 360 {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    static func frame(from result: PoseLandmarkerResult, timestampMs: Int64) -> PoseFrame {
        guard let normalized = result.landmarks.first else {
            return PoseFrame(points: [], visibility: [], world: [], timestampMs: timestampMs)
        }

        var points = [P2](repeating: P2(x: 0, y: 0), count: Lm.count)
        var visibility = [Float](repeating: 0, count: Lm.count)
        for (index, landmark) in normalized.prefix(Lm.count).enumerated() {
            points[index] = P2(x: Double(landmark.x), y: Double(landmark.y))
            visibility[index] = landmark.visibility?.floatValue ?? 0
        }

        var world = [P3](repeating: P3(x: 0, y: 0, z: 0), count: Lm.count)
        if let source = result.worldLandmarks.first {
            for (index, landmark) in source.prefix(Lm.count).enumerated() {
                world[index] = P3(x: Double(landmark.x), y: Double(landmark.y), z: Double(landmark.z))
            }
        } else {
            world.removeAll()
        }
        return PoseFrame(points: points, visibility: visibility, world: world, timestampMs: timestampMs)
    }
}
