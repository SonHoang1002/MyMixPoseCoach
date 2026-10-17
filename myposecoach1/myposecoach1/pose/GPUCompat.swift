import CoreML
import Foundation
import Metal
import Vision

/// Nhận diện GPU có driver lỗi và ép các request Vision tránh GPU trên máy đó.
///
/// Trên GPU A13, framework Metal/Espresso của iOS mới gửi selector `resourceIndex`
/// tới `AGXA13FamilyFunctionHandle` mà driver không trả lời → NSException, Swift
/// không bắt được. Lỗi KHÔNG riêng MediaPipe: Apple Vision chạy model trên GPU cũng
/// sập y hệt (log thực tế: MediaPipe đã bị bỏ qua, Vision 3D vẫn làm chết app).
nonisolated enum GPUCompat {

    /// Theo bảng Metal của Apple, A13 là Apple family 6 còn A14 bắt đầu ở family 7.
    /// GPU family có tính bao hàm, nên phải kiểm tra `apple6 && !apple7`.
    static let isA13: Bool = {
        guard let gpu = MTLCreateSystemDefaultDevice() else { return false }
        return gpu.supportsFamily(.apple6) && !gpu.supportsFamily(.apple7)
    }()

    /// Mọi request Vision của app phải đi qua đây trước `perform`.
    ///
    /// Trả `false` nếu có giai đoạn tính toán không chọn được CPU — bên gọi phải bỏ
    /// request đó trên máy A13 thay vì để nó tự rơi vào GPU.
    @discardableResult
    static func avoidGPUIfNeeded(_ request: VNRequest) -> Bool {
        guard isA13 else { return true }
        guard let stages = try? request.supportedComputeStageDevices else { return false }
        for (stage, devices) in stages {
            guard let cpu = devices.first(where: {
                if case .cpu = $0 { return true }
                return false
            }) else { return false }
            request.setComputeDevice(cpu, for: stage)
        }
        return true
    }
}
