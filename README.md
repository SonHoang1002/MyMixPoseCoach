# MyMixPoseCoach iOS

Repository này đã mang theo hai model cần lúc chạy:

- `myposecoach1/myposecoach1/pose_landmarker_full.task`
- `myposecoach1/myposecoach1/geocalib/geocalib-mang-int8.onnx`

MediaPipe, ONNX Runtime và ML Kit được khóa phiên bản trong project/lockfile và được tải tự động khi chuẩn bị build. Không commit thư mục `Pods`, `DerivedData` hay cache Swift Package vì chúng rất lớn và phụ thuộc máy.

## Build trên máy mới

Yêu cầu: máy Mac Apple Silicon, Xcode 26.4 trở lên và kết nối mạng ở lần build đầu tiên. Binary MediaPipe 1.1.0 hiện chỉ cung cấp simulator `arm64`, không có simulator `x86_64` cho Mac Intel.

```bash
git clone https://github.com/BNNam299/MyMixPoseCoach.git
cd MyMixPoseCoach
git switch phuong-an-tich-hop-ios
./build-ios.sh
```

`build-ios.sh` tự kiểm tra checksum model, cài đúng CocoaPods 1.16.2 nếu máy chưa có, chạy `pod install`, tải các Swift Package đã khóa revision và build app cho iOS Simulator.

Nếu chỉ muốn cài dependency rồi mở Xcode:

```bash
./bootstrap-ios.sh --open
```

Sau đó luôn mở `myposecoach1/myposecoach1.xcworkspace`, không mở trực tiếp file `.xcodeproj`.
