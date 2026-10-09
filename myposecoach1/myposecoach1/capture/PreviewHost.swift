import AVFoundation
import SwiftUI

// Bọc `AVCaptureVideoPreviewLayer` thành một UIView để SwiftUI dựng được — nơi
// tương đương `PreviewView` của CameraX trên Android.
//
// AVFoundation không có control xem trước sẵn như PreviewView; frame của layer
// phải đuổi theo kích thước UIView mỗi khi bố cục đổi, nên mọi việc đó gom vào
// `PreviewUIView.layoutSubviews`.
struct PreviewHost: UIViewRepresentable {
    var layer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> PreviewUIView {
        PreviewUIView()
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.set(cameraLayer: layer)
    }
}

/// UIView giữ vững khung hình của layer xem trước mỗi khi bố cục đổi.
final class PreviewUIView: UIView {
    private var cameraLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        // SwiftUI đưa frame sau cùng vào đây — gắn lại mỗi lần là giữ đúng vùng.
        cameraLayer?.frame = bounds
    }

    /// Gắn hoặc gỡ camera layer. Gỡ (`nil`) khi màn hình rời đi.
    func set(cameraLayer layer: AVCaptureVideoPreviewLayer?) {
        if cameraLayer === layer { return }
        cameraLayer?.removeFromSuperlayer()
        cameraLayer = layer
        guard let layer else { return }
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        self.layer.insertSublayer(layer, at: 0)
    }
}