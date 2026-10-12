# MyMixPoseCoach iOS

Repo chứa sẵn toàn bộ asset runtime của app:

- `pose_landmarker_full.task` — model MediaPipe Pose.
- `geocalib-mang-int8.onnx` — model GeoCalib.
- 13 ảnh template trong `myposecoach1/myposecoach1/templates/`.
- `Podfile.lock` cho ML Kit và hai `Package.resolved` cho MediaPipe/ONNX Runtime.
- Submodule Android `posecoach` được ghim đúng commit làm nguồn thuật toán tham chiếu.

Thư mục sinh tự động như `Pods`, Swift Package cache và `DerivedData` không được
commit vì phụ thuộc phiên bản Xcode/máy build. Script bên dưới tự tải đúng phiên
bản đã khóa và kiểm tra checksum trước lẫn sau khi build.

## Build trên máy mới

Yêu cầu duy nhất là macOS, Xcode 26.4 trở lên và kết nối mạng trong lần build đầu.
Xcode và iOS SDK không thể phân phối trong Git repository.

```bash
git clone --recurse-submodules -b phuong-an-tich-hop-ios \
  https://github.com/BNNam299/MyMixPoseCoach.git
cd MyMixPoseCoach
./build-ios.sh
```

`build-ios.sh` tự thực hiện toàn bộ các bước:

1. Khởi tạo/cập nhật submodule Android đúng commit.
2. Kiểm tra checksum 2 model và 13 template được Git theo dõi.
3. Cài CocoaPods 1.16.2 cho user hiện tại nếu máy chưa có.
4. Khôi phục Pods đúng `Podfile.lock`.
5. Khôi phục Swift Packages đúng revision trong `Package.resolved`.
6. Build app cho thiết bị iOS mà không yêu cầu chứng chỉ ký mã.
7. Kiểm tra app bundle cuối cùng có đủ 15 asset và đúng checksum.

Build thành công nằm tại `.build/DerivedData/Build/Products/Debug-iphoneos/myposecoach1.app`.

Nếu chỉ muốn chuẩn bị dependency rồi mở Xcode:

```bash
./bootstrap-ios.sh --open
```

Cũng có thể nhấp đúp `setup-ios.command` trong Finder để chạy đúng bước trên.

Luôn mở `myposecoach1/myposecoach1.xcworkspace`, không mở trực tiếp `.xcodeproj`.
ML Kit cho iOS được Google phát hành qua CocoaPods, nên `pod install` là bước bắt
buộc; script đã tự động hóa bước này.

Project không ghim Apple Development Team của người tạo repo. Khi muốn chạy trên
iPhone thật, chọn team của bạn trong **Signing & Capabilities**; lệnh build kiểm
tra ở trên không cần tài khoản Apple hay chứng chỉ ký mã.

Sau khi PR được merge vào repo chính, có thể clone nhánh `iosv1` từ
`https://github.com/SonHoang1002/MyMixPoseCoach.git` bằng cùng quy trình.
