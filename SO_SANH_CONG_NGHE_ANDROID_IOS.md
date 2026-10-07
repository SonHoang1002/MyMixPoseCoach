# So sánh công nghệ: Bản Android (`posecoach`) ↔ Bản iOS (sắp dựng)

> Nguồn: đọc thẳng code Android + tài liệu chính thức của Google/Apple (kiểm ngày 06/10/2026).
> Mục đích: chọn đúng cầu nối nền tảng khi dựng bản iOS **100% tương đương chức năng**,
> không phá 6 bất biến của dự án.

---

## 1. Quyết định quan trọng nhất: nhận diện khung xương

| | MediaPipe PoseLandmarker (đang dùng trên Android) | Apple Vision (thay thế thuần Apple) |
|---|---|---|
| **Có trên iOS không?** | ✅ **CÓ** — `MediaPipeTasksVision`, API đặt tên gần như trùng Android | ✅ `VNDetectHumanBodyPoseRequest` (2D), `VNDetectHumanBodyPose3DRequest` (3D, iOS 17+) |
| **Cài đặt** | CocoaPods chính thức (`pod 'MediaPipeTasksVision'`); hoặc SPM qua wrapper `paescebu/SwiftTasksVision` | Hệ thống, không cần cài |
| **Chạy 3 mode** | `.image` / `.video` / `.liveStream` — **trùng khớp 1-1** với 3 chỗ gọi `IMAGE`/`VIDEO`/`LIVE_STREAM` của Android | Một API `VNImageRequestHandler.perform` cho cả ảnh tĩnh; camera thì `VNSequenceRequestHandler` |
| **Số điểm** | **33** (`Lm.NOSE` → `Lm.MOUTH_RIGHT`, bao gồm mắt/tai/miệng/heel/foot/pinky/thumb) | 2D: ~19 khớp (`nose`, `leftEye`, `leftEar`, `neck`, `root`, vai/khủy/cổ tay/hông/gối/cổ chân) — **không có miệng, gót, mũi bàn chân, ngón tay**. 3D: **17 khớp** |
| **`worldLandmarks` (3D, mét)** | ✅ có, gốc = trung điểm hai hông, **cùng đơn vị mét** | 3D: ✅ nhưng **iOS 17+**, gốc = `root`, chỉ 17 khớp; 2D: ❌ không có |
| **Toạ độ 2D** | 0..1, **y hướng XUỐNG**, x trái→phải | 0..1, **y hướng LÊN** (góc dưới-trái), cần lật |
| **Độ nhiễu / model** | Model `.task` **cùng file** với Android | Model khác hẳn → **số đo khác, ngưỡng khác** |
| **Ảnh mẫu quay lưng** | ✅ đã kiểm chứng 280/280 khung không mất dấu | Chưa kiểm; Vision nổi tiếng kém hơn với người quay lưng |

### ⭐ Khuyến nghị: **dùng MediaPipe trên iOS luôn**

| Vì sao | Hệ quả nếu bỏ |
|---|---|
| Cùng model `.task` → cùng 33 điểm, cùng quy ước y-down, cùng đơn vị mét | Không phải viết lại `Lm`/`P2`/`P3`, không phải lật trục rải rác (FOOTGUNS 3) |
| **Cùng hàm đo → cùng độ nhiễu** → **mọi ngưỡng trong `GuidanceConfig` và `Criterion.reference` giữ nguyên số** | Dùng Vision thì model khác, nhiễu khác → **buổi đo máy thật phải làm lại từ đầu**, mọi con số đo được trên Android mất giá trị |
| API `.image`/`.video`/`.liveStream` + `detectAsync(image:timestampInMilliseconds:)` giống hệt | Port `PoseDetector.kt`几乎是直接改 cú pháp |
| Nhóm ảnh mẫu **quay lưng** (đang trong scope) giữ nguyên độ ổn định | Vision chưa kiểm → có thể mất cả nhóm template |

**Nhược điểm phải chấp nhận:** thêm 1 dependency bên thứ 3 (Google) thay vì SDK hệ thống.
Quy tắc dự án: *trước khi thêm thư viện ngoài bảng → dừng lại hỏi người dùng*.

---

## 2. Bảng ánh xạ từng mảng

| # | Mảng | Android (đang dùng) | iOS (đề xuất) | Rủi ro khi port |
|---|---|---|---|---|
| 1 | Khung xương người | **MediaPipe Pose Landmarker** `pose_landmarker_full.task`, `tasks-vision 1.0.0`, delegate `CPU`, `numPoses=1` | **MediaPipeTasksVision** — cùng model `.task` | 🟡 Package chính thức là CocoaPods; SPM cần wrapper bên thứ 3 → **phải chốt sớm vì ảnh hưởng cấu trúc project** |
| 2 | 3 mode gọi model | `RunningMode.IMAGE` (ảnh mẫu) / `VIDEO` (chấm khung sau quay) / `LIVE_STREAM` (camera) | `.image` / `.video` / `.liveStream` | 🟢 Map 1-1 |
| 3 | Timestamp LIVE_STREAM | `SystemClock.uptimeMillis()` + ép tăng nghiêm ngạt (`lastSentTimestamp + 1`) | `Int` ms, ép tăng tương tự | 🟡 Hai khung cùng ms → MediaPipe ném lỗi (đã ghi ở Android) |
| 4 | Khoá chống SIGBUS | `MediaPipeGuard.serialized` bọc tạo/huỷ | Cần khoá serial queue tương đương (`NSLock`/serial `DispatchQueue`) | 🔴 **Thiếu là sập tầng C++**, không có thông báo lỗi |
| 5 | Xoay ảnh trước khi nhận diện | `Bitmap.rotate(rotationDegrees)` (FOOTGUNS 5: sai chỗ này thì X/Y hoán đổi, **không crash**) | Xoay `CVPixelBuffer` về upright, hoặc để `MPImage` tự áp `orientation` | 🔴 Đọc lại `UprightBitmap.kt` + `VideoFrameSource.kt` để làm đúng |
| 6 | Góc mặt + mắt nhắm | **ML Kit Face** `headEulerAngleY`, `left/rightEyeOpenProbability` (đồng bộ qua `Tasks.await`, timeout 3s) | `VNDetectFaceLandmarksRequest` (không có sẵn euler angle → tự suy từ mũi/mắt) **hoặc** MediaPipe `FaceLandmarker` | 🟡 **Khác đơn vị/sự kiện**: ML Kit trả 0..1 xác suất; Vision chỉ có landmark → phải tự tính độ mở mắt. Chỉ dùng cho (a) yaw ảnh chân dung, (b) mục hậu kỳ `EYES_OPEN` → ảnh hưởng nhỏ nhưng **cần nói rõ với PO** |
| 7 | Camera xem trước + quay | **CameraX** `Preview` + `ImageAnalysis` + `VideoCapture` (`camera 1.6.2`) | `AVCaptureSession` + `AVCaptureVideoDataOutput` (lấy frame cho model) + `AVCaptureMovieFileOutput` (hoặc `AVAssetWriter`) | 🔴 Tách 2 output đòi **cùng 1 `CMSampleBuffer` phải đi 2 đường** → dễ tốn bộ nhớ; cần chốt `AVAssetWriter` ghi thẳng từ buffer |
| 8 | Zoom ratio | `zoomRatio` (CameraX, 1.0 = gốc) | `AVCaptureDevice.videoZoomFactor` (1.0 = 0.5x trên iPhone) | 🔴 **Khác thang!** iPhone `videoZoomFactor=1` ≈ ống rộng 0.5x → phải quy đổi về đúng thang `zoomRatio` của Android, nếu không `DistanceEstimator` + `ZOOM_LECH_TOI_DA` + `zoomToiDa` sai hết |
| 9 | Góc mở dọc ống kính | `vFovDeg` đọc từ phần cứng/ Camera2 | `AVCaptureDevice.activeFormat.videoFieldOfView` (⚠️ là **ngang**, phải quy về dọc theo tỉ lệ khung) | 🟡 Sai chỗ này là `DistanceEstimator.heSoOngKinh` sai → số bước chân sai |
| 10 | Cảm biến nghiêng máy | `SensorManager` `TYPE_GRAVITY` + `TYPE_GYROSCOPE`, `SENSOR_DELAY_GAME` | `CMMotionManager` → `deviceMotion.gravity` + `deviceMotion.rotationRate` | 🔴 **Quy ước trục Z ĐẢO NGƯỢC**: Android mặt ngửa → `(0,0,+g)`; CoreMotion mặt ngửa → `(0,0,-1)`. Công thức `sinPitch = -gz/|g|` phải **đảo dấu và kiểm lại 3 tư thế** đúng như comment trong `DeviceTilt.kt` |
| 11 | Tại sao không dùng `attitude.pitch` | — | ⚠️ **ĐÃ CÓ BÀI HỌC**: bị "khoá gimbal" khi cầm máy dựng đứng (tư thế chụp dọc phổ biến nhất) → phải lấy từ **vector trọng lực** | 🔴 Đúng cái lỗi iOS cũ từng mắc |
| 12 | Giao diện | **Jetpack Compose** + Material 3, BOM `2026.02.01` | **SwiftUI** | 🟡 Không có Material; token màu/spacing phải tự port từ `DesignTokens.kt` |
| 13 | Kiến trúc màn hình | `XxxUiState` + `XxxAction` + `XxxViewModel.onAction()` + `StateFlow` | `@Observable` model + `View` (Observation, iOS 17+) hoặc `ObservableObject` | 🟡 Chọn `@Observable` thì floor = iOS 17 |
| 14 | Điều hướng | Navigation Compose (Nav 2) | `NavigationStack` + `NavigationPath` | 🟢 Đơn giản hơn Android |
| 15 | Ảnh: xoay EXIF | `UprightBitmap.kt` (MediaMetadataRetriever + EXIF) | `CGImageSource` + `kCGImagePropertyOrientation`, hoặc `UIImage.normalized()` | 🟡 Sai hướng = sai bố cục mà không crash |
| 16 | Trích khung từ video | `VideoFrameSource` (`MediaMetadataRetriever.getFrameAtTime`) | `AVAssetImageGenerator` (`appliesPreferredTrackTransform = true`) | 🟡 Đọc lại `VideoFrameSource.kt` để giữ cùng cách chọn mốc thời gian |
| 17 | Chọn ảnh từ máy người dùng | Photo Picker (`ActivityResultContracts.PickVisualMedia`) — **không cần quyền** | `PHPickerViewController` — **không cần quyền** | 🟢 Tương đương, không cần `READ_MEDIA` |
| 18 | Lưu ảnh tạm + chống rác | `ShotStore` trong `filesDir` (app-private, 4 lớp GC) | `Caches/` hoặc `Documents/` (app-sandbox, không cần quyền) | 🟢 |
| 19 | Quyền | `CAMERA` trong Manifest + `uses-feature gyroscope required=true` | `Info.plist`: `NSCameraUsageDescription`, `NSMotionUsageDescription` | 🟡 **iOS không có `uses-feature`** → phải **kiểm tra lúc chạy** (`CMMotionManager.isDeviceMotionAvailable`) và tự chặn thông báo rõ ràng |
| 20 | Kiểm thử | JUnit 4 (11 file test, ~2.500 dòng) | XCTest / Swift Testing | 🟡 Logic thuần (`CriterionGate`, `ShotScorer`, `BestShotBuffer`, `CuePresenter`) port nguyên trạng thái được; **phép port sẽ có test đối chiếu** |

---

## 3. Cái KHÔNG được đổi khi port (dẫn xuất từ bảng trên)

| # | Bất biến | Ý nghĩa với iOS |
|---|---|---|
| 1 | **Một hàm đo duy nhất** (`Measurer.measure`) | Dùng MediaPipe trên iOS thì hàm này port **nguyên xi**, không viết phép đo thứ hai |
| 2 | **`FramingClass` suy 1 lần từ ảnh mẫu** | Giữ nguyên, không cho camera tự chọn |
| 3 | **Ngưỡng ở 1 chỗ** (`GuidanceConfig`) | Nếu dùng Vision → **mọi số phải đo lại**. Nếu dùng MediaPipe → giữ nguyên số, chỉ chờ buổi đo xác nhận |
| 4 | **Không đo được ≠ sai** (`GateState.UNMEASURED`) | Logic thuần, port 1-1 |
| 5 | **Ảnh mẫu qua cổng 3 mức trước màn camera** | `TemplateGate` port nguyên |
| 6 | **Không thất bại âm thầm** | Mọi `return` sớm phải hiện lời nhắn tiếng Việt |

---

## 4. Những thứ iOS làm **GIỐNG** nhưng số **KHÁC** (bẫy kinh điển)

| Chỗ | Android | iOS | Nếu không xử lý |
|---|---|---|---|
| Toạ độ y | 0 = mép trên, y **tăng xuống** | Vision 2D: 0 = mép dưới, y **tăng lên** | Mọi mục dọc sai có hệ thống, **không crash** (đã ghi ở FOOTGUNS) |
| Zoom | `zoomRatio` 1.0 = ống kính gốc | `videoZoomFactor` 1.0 = ống kính **rộng nhất** (0.5x) | `DistanceEstimator` và câu "lùi 2 bước" sai hết |
| Góc mở ống kính | vFOV dọc | `videoFieldOfView` **ngang** | Số bước chân sai |
| Trọng lực | gz = +9.81 khi mặt ngửa | gravity z = **−1** khi mặt ngửa | Cảm biến đảo chiều → câu "chúc máy" nói ngược |
| Yaw euler | ML Kit `headEulerAngleY`, 0 = thẳng | Vision không có sẵn | Phải tự tính, hoặc dùng `FaceLandmarker` |
| Bộ nhớ model | `.task` để `noCompress` trong APK | `.task` trong bundle | — |

---

## 5. Cần chốt trước khi code

1. **MediaPipe (khuyên dùng) hay Vision thuần Apple?** — quyết định này quyết định ngưỡng có giữ được số không.
2. **Cách cài MediaPipe trên iOS**: CocoaPods chính thức (thêm `Podfile`) hay SPM qua wrapper bên thứ 3.
3. **Floor iOS**: `@Observable` + MediaPipe → iOS 15+ (MediaPipe hỗ trợ từ iOS 12); nếu bắt buộc Vision 3D → iOS 17.
4. **App ID**: bundle hiện tại là `myposecoach1` (tên Xcode mặc định) — Android có luật *"không để `com.example` khi phát hành"*, iOS cũng vậy.
