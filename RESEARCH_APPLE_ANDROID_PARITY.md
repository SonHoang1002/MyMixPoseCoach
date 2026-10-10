# Phương án Apple giữ chất lượng tương đồng Android

Ngày nghiên cứu: 10/10/2026. Đây là kết quả đọc source và tài liệu chính thức, chưa phải benchmark trên iPhone.

## 1. Kết luận

Khuyến nghị kiến trúc kết hợp: SwiftUI + AVFoundation + CoreMotion cho nền tảng Apple; MediaPipe Pose và ML Kit cho nhận diện tương ứng Android; ONNX Runtime CPU với nguyên file GeoCalib int8 làm bản đối chiếu; Kotlin Multiplatform (KMP) cho logic thuần dùng chung. Core ML chỉ là nhánh tăng tốc sau khi chứng minh được chất lượng.

Đây là lựa chọn ưu tiên khả năng đối chiếu và bảo trì. Chưa thể gọi là cấu hình nhanh nhất hoặc xác nhận chất lượng tương đồng nếu chưa chạy trên thiết bị. KMP giữ thuật toán chung, không tự làm các bộ nhận diện trả số giống nhau và không phải công cụ tăng tốc suy luận.

## 2. Chuẩn Android và hiện trạng iOS

- Chuẩn: working tree `Pj-demo`, nhánh `phuong-an-tich-hop`, HEAD `5993ab3`, bao gồm thay đổi chưa commit và file chưa được theo dõi. Phải chụp mốc các file, cấu hình và model trước khi nghiệm thu để tránh chuẩn di chuyển trong lúc so.
- iOS: nhánh `iosv1`, HEAD `b9349fe`. Có các lớp Swift tương ứng tầng đo, chấm điểm, hướng dẫn tuần tự, gate và bộ giữ ảnh Android. Đang dùng Vision cho cơ thể và mặt; mắt mở chưa đo được; thiếu GeoCalib, ML Kit labeling và luồng scene tương ứng.
- `pose/VisionPose.swift` ghi MediaPipeTasksVision 1.0.0 từng crash với `AGXA13FamilyFunctionHandle resourceIndex`. Chưa có crash log trong bằng chứng đã đọc, chưa tái hiện trên máy thật, chưa tìm thấy issue công khai khớp chính xác. Không coi comment là bằng chứng mọi bản MediaPipe đều hỏng hoặc bản mới chắc chắn đã sửa.
- File ONNX Android: 30.747.161 byte; SHA-256 `7e63366ef8b9acbe4a2350633d415015c5f4143fc9605057d5ca4734c73a5814`. Đọc graph protobuf trực tiếp xác nhận 304 `ConvInteger`, 259 `DynamicQuantizeLinear`, cùng các toán tử float. Có cả 2 `RandomUniformLike`; cần kiểm chúng có ảnh hưởng đầu ra hay bị tối ưu bỏ trước khi giả định kết quả hoàn toàn xác định.

## 3. Lựa chọn theo thành phần

| Thành phần | Chọn ban đầu | Cách tối ưu giữ chất lượng |
|---|---|---|
| Cơ thể 2D/3D | MediaPipe Tasks Vision, nguyên `pose_landmarker_full.task` | Giữ model Full, numPoses=1, cấu hình confidence và 3 running mode như Android; giảm nhịp gọi/chi phí ảnh trước khi đổi model |
| Mặt | ML Kit Face Detection iOS | FAST, classification ALL, landmark/contour NONE, minFaceSize 0.15 như source Android; giữ quy tắc chọn mặt lớn nhất và null |
| Nhãn bối cảnh/kiểu chụp | ML Kit Image Labeling iOS | Giữ nhãn thô và confidence; chạy lúc nhập hoặc theo nhịp lấy mẫu scene, không chạy trong mọi vòng pose |
| Góc máy ảnh mẫu | ONNX Runtime CPU, nguyên GeoCalib int8 | Chạy một lần lúc phân tích ảnh; tái sử dụng session, cache theo ảnh/model/preprocessing; benchmark số thread |
| Bộ giải góc | `GiaiPhoiCanh` dùng chung qua KMP | Giữ Double, thứ tự tính, lưới và điều kiện hội tụ; chỉ tối ưu sau khi có test số |
| Hướng dẫn/chấm/chọn ảnh | Module KMP logic thuần | Truyền landmark, face, cảm biến và timestamp; trả trạng thái/câu có cấu trúc, không truyền ảnh qua Swift–Kotlin |
| Camera/cảm biến/UI | AVFoundation, CoreMotion, SwiftUI | Phần riêng Apple; chuẩn hóa hướng, mirror, zoom và vùng cắt thành cùng hợp đồng dữ liệu |

MediaPipe chính thức có 33 landmark và world landmark, và nhận UIImage/CVPixelBuffer/CMSampleBuffer. Live stream bỏ frame mới khi đang bận. Không dùng mirrored orientation cho Pose Landmarker; cần chuẩn hóa mirror theo hợp đồng ảnh sẽ lưu ở lớp bọc. [Hướng dẫn iOS](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/ios).

Tài liệu setup hiện mô tả CPU trên iOS. Có SPM chính thức: manifest hiện trỏ binary 1.1.0, floor iOS 15. Release 1.1.0 ngày 07/10/2026; không có xác nhận trong release được đọc rằng đúng crash local đã chữa. Ghim revision/phiên bản đã kiểm chứng, không theo master tự động. Manifest có `-all_load` và dependency chung nhiều Tasks; cần kiểm kích thước và xung đột linker với ML Kit/ORT trên device lẫn simulator. [Setup](https://developers.google.com/edge/mediapipe/solutions/setup_ios), [manifest](https://github.com/google-ai-edge/mediapipe/blob/master/Package.swift), [release](https://github.com/google-ai-edge/mediapipe/releases/tag/v1.1.0).

ML Kit có cả hai gói iOS chính thức. Tài liệu hiện ví dụ `GoogleMLKit/FaceDetection` và `GoogleMLKit/ImageLabeling` 8.0.0 qua CocoaPods. Cùng họ SDK giúp giảm khác biệt ngữ nghĩa, nhưng tài liệu không bảo đảm đầu ra Android/iOS bằng từng bit. Kiểm trực tiếp yaw, mắt mở, tên/chỉ số nhãn và confidence. [Face](https://developers.google.com/ml-kit/vision/face-detection/ios), [Labeling](https://developers.google.com/ml-kit/vision/image-labeling/ios).

## 4. Vì sao chưa chọn Vision hoặc Core ML cho mọi thứ

Vision hiện tại thay bộ nhận diện, số điểm, confidence và cấu trúc 3D. Mảng 33 phần tử không có nghĩa là 33 phép đo tương đương: source lặp lại điểm mắt, thiếu điểm miệng và dùng centerHead thay nose 3D. Những khác biệt này đi vào faceBox, headPoint, yaw, phép lọc chi chĩa vào ống kính và phối cảnh. Chưa có bằng chứng Vision kém hơn MediaPipe một cách tổng quát; ở dự án này điều chắc chắn là hai đầu ra không cùng hợp đồng đã được hiệu chỉnh.

Chuyển nguyên BlazePose sang Core ML cũng không chỉ là đổi định dạng trọng số. Cần giữ detector, ROI, xoay/cắt, giải landmark, tracking và smoothing. Core ML Tools Unified Conversion API tài liệu hỗ trợ nguồn TensorFlow/PyTorch; không có đường trực tiếp chính thức từ gói MediaPipe `.task` hoàn chỉnh. Đây là một dự án chuyển pipeline riêng, chưa phải phương án tối ưu chi phí ban đầu. [Nguồn chuyển đổi Apple](https://apple.github.io/coremltools/docs-guides/source/target-conversion-formats.html).

GeoCalib phù hợp thử Core ML hơn vì đã tách mạng và bộ giải. Tuy nhiên, factory Core ML EP của ONNX Runtime v1.24.2 không đăng ký `ConvInteger`/`DynamicQuantizeLinear`. Suy luận từ graph local và source ORT: bản int8 hiện tại không có cơ sở để kỳ vọng toàn mạng chạy trên Neural Engine; phần không được hỗ trợ có thể ở CPU, gây phân mảnh và overhead. Phải xem profiling của session sau graph optimization, không chỉ đếm node nguồn. [Factory v1.24.2](https://github.com/microsoft/onnxruntime/blob/v1.24.2/onnxruntime/core/providers/coreml/builders/op_builder_factory.cc).

Nhánh tăng tốc đề xuất: từ checkpoint/mạng float gốc, thử ONNX float với Core ML EP hoặc chuyển trực tiếp PyTorch sang Core ML ML Program, sau đó thử FP16. Giữ nhiều kích thước đầu vào hoặc shape phù hợp tỉ lệ gốc; không ép ảnh chữ nhật thành vuông hoặc cắt mất nền chỉ để đạt shape tĩnh. So map đầu ra và pitch/roll/FOV cuối với bản int8 chuẩn. Không bỏ CPU fallback trước khi đo. [Core ML EP](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html).

## 5. Tối ưu Apple có thể làm mà không đổi thuật toán

1. Camera preview/ghi vẫn theo chất lượng chụp; nhánh nhận diện dùng buffer riêng ở kích thước đã đối chiếu. Ưu tiên buffer trực tiếp, tái sử dụng tài nguyên; tránh chuyển mỗi frame qua UIImage/JPEG rồi giải mã lại.
2. Giữ một việc pose đang chạy, bỏ frame cũ thay vì xếp hàng. Dùng timestamp đơn điệu và thống nhất đơn vị. Không chặn callback camera bằng công việc nặng. Apple hướng dẫn bỏ frame trễ và theo dõi nguyên nhân drop; source iOS đã bật `alwaysDiscardsLateVideoFrames`. [TN2445](https://developer.apple.com/library/archive/technotes/tn2445/_index.html).
3. Mặt live khởi điểm 300 ms/lần, quá 600 ms thì bỏ như Android. Hậu kỳ đọc mặt ở ảnh đủ nét/cỡ lớn; không thu nhỏ mặt tới mức mất thông tin mắt. Google hướng dẫn mặt tối thiểu khoảng 100×100 pixel cho detect thông thường. [ML Kit iOS](https://developers.google.com/ml-kit/vision/face-detection/ios).
4. GeoCalib chạy ngoài vòng live, một lần mỗi ảnh mẫu. Giữ tiền xử lý Android: cạnh ngắn 320, crop giữa về bội 32, RGB [0,1], CHW; kiểm cả cách resize vì Apple/Android có thể nội suy khác.
5. Chỉ dữ liệu nhỏ qua Swift–KMP; tensor và ảnh ở Swift/native. KMP gom phép đo, profile, scorer, gate, cue, best-shot buffer, từ điển scene và solver; file I/O, SDK và UI ở nền tảng. Tách UiText khỏi R.string, giữ code câu/bên/tham số và dịch tại UI. [JetBrains: cấu trúc khi giữ UI native](https://kotlinlang.org/docs/multiplatform/multiplatform-project-recommended-structure.html).
6. Ảnh chụp liên tục giữ mục tiêu 3024 cạnh ngắn và chất lượng encode tương đương Android; ảnh từ video 1440 theo chuẩn hiện tại. Không dùng một preset cho cả hai đường. Điểm nét phải so trên cùng ROI, độ phân giải và thang màu; khác resize là khác điểm nét.
7. Tối ưu năng lượng bằng nhịp gọi và quản lý nhiệt trước khi đổi Full sang Lite. Nếu không giữ được tốc độ tối thiểu khi nóng, ghi rõ hạn chế thay vì âm thầm đổi model và coi như chất lượng vẫn bằng nhau.

## 6. Nghiệm thu “tương đồng”

Các ngưỡng dưới là đề xuất nghiệm thu, chưa phải kết quả đạt hay quyết định sản phẩm đã chốt.

| Lớp kiểm | Dữ liệu | Điều cần chứng minh |
|---|---|---|
| Logic chung | Landmark/face/cảm biến ghi từ Android, cùng timestamp | Gate, bước, cue, skipped, countdown cùng hành vi; số đo/scorer/solver trong tolerance số học đã định |
| Nhận diện trên cùng media | Ảnh và video byte giống nhau, cùng mode, hướng/crop | Pose không mất nhóm quay lưng; sai lệch mốc không đẩy tiêu chí qua gate thường xuyên; mặt/nhãn không rớt chức năng |
| Trải nghiệm | Cùng video và template, đủ 5 lớp, selfie/gương/trên/ngang/dưới | Mục tiêu ban đầu >=95% trạng thái tiêu chí khớp trên frame so được; phân tích riêng vùng sát ngưỡng, không che lỗi bằng bỏ frame thiếu |
| Chọn ảnh | Cùng video, cùng mốc sample | Ít nhất 4/5 khoảnh khắc lựa chọn tương ứng trong cửa sổ thời gian đa dạng hiện tại; người đánh giá không thấy suy giảm mắt mở, crop hoặc dáng |
| Hiệu năng | iPhone đời thấp được hỗ trợ và máy mới, phiên liên tục >=10 phút | Vòng đo >=8–10 Hz; cue P95 <350 ms; không backlog hoặc crash; ghi FPS, p50/p95, RAM đỉnh, pin và nhiệt |
| Camera thật | Android và iPhone cùng cảnh, gồm đổi lens/zoom | Kiểm mapping zoom, FOV, gravity, mirror; không mong pixel ảnh hai camera giống nhau |

Tách tỷ lệ đo được khỏi độ chính xác: không tính thiếu mốc là khớp; không renormalize điểm rồi dùng điểm cao chứng minh nhận diện tốt. Bộ dữ liệu phải có che vai, kính/mũ, nhiều người, chân ngoài khung, chân chĩa vào máy, ngồi, nền ít đường, cầu thang, chúc gắt, mất dấu và mở lại phiên.

## 7. Trình tự triển khai tối ưu chi phí

1. Chụp mốc Android local và dataset; giữ thuật toán đang chạy.
2. Spike MediaPipe iOS riêng: chạy sample tối giản với đúng model, CPU, segmentation tắt; ghi device/iOS/build/SDK/crash log. So 1.0.0 với bản mới nếu tái hiện được. Đây là cổng quyết định trước khi di chuyển kiến trúc.
3. Spike ML Kit Face + Labeling và GeoCalib ORT CPU; chạy bộ media chung. Kiểm linker khi ghép ba SDK.
4. Nếu nhận diện đạt, tách KMP logic theo từng nhóm và chuyển test Android, rồi nối SwiftUI hiện tại; không viết lại giao diện chỉ để dùng KMP.
5. Profile end-to-end. Chỉ nếu GeoCalib là nút thắt mới thử Core ML/FP16; nếu camera live chậm, giảm chi phí copy/nhịp gọi trước.
6. Nếu MediaPipe vẫn crash, cân nhắc bản build CPU tùy chỉnh hoặc runtime khác giữ nguyên pipeline. Vision chỉ được chấp nhận làm bản thay thế khi qua bộ nghiệm thu, không đổi âm thầm theo từng frame.

## 8. Kiểm tra nguồn và giới hạn

Qua GitHub API khi nghiên cứu: MediaPipe, ONNX Runtime SPM và GeoCalib đều tồn tại, không archived; lần push lần lượt 09/10/2026 UTC, 11/09/2026 UTC, 16/08/2026 UTC. [MediaPipe](https://github.com/google-ai-edge/mediapipe), [ORT SPM](https://github.com/microsoft/onnxruntime-swift-package-manager), [GeoCalib](https://github.com/cvg/GeoCalib).

Manifest ORT SPM hiện trỏ binary 1.24.2; đây là trạng thái manifest đã đọc, không khẳng định runtime Android đang cùng bản hoặc đây là phiên bản nên nâng ngay. [Manifest ORT](https://github.com/microsoft/onnxruntime-swift-package-manager/blob/main/Package.swift).

Không có Mac/iPhone trong môi trường đã sử dụng để benchmark. Lần import onnx bằng venv nghiên cứu Android gặp lỗi protobuf; không sửa môi trường đó. Thống kê toán tử được đọc bằng protobuf wire parser độc lập, chưa chạy ONNX checker hay inference trên iOS. File này không thay thế kết quả spike và chưa thêm dependency hoặc sửa source app.
