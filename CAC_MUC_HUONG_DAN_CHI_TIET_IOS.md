# Chi tiết từng mục hướng dẫn trên bản iOS — đo gì, dùng công nghệ nào, làm được chưa

> Tài liệu này viết riêng cho bản iOS (`myposecoach1/`), đối chiếu thẳng với code đang có
> (kiểm **10/10/2026**) và các tài liệu gốc trong `posecoach/`. Mục đích: với **mỗi tiêu chí**,
> trả lời đủ 4 câu để lập trình không cần đoán:
>
> 1. Tiêu chí này **đo đại lượng gì** (đơn vị, dấu, thang)?
> 2. Lấy số từ **API/Công nghệ nào của iOS** (ảnh mẫu khác camera ở đúng chỗ nào)?
> 3. **Ngưỡng hiện tại** trong `GuidanceConfig` là bao nhiêu, đã đo máy thật chưa?
> 4. Nếu công nghệ hiện tại **không giải quyết được** thì **đổi sang gì** (ưu tiên framework
>    có sẵn của iOS)?

Bảy mục người dùng nêu, tên trong code (`Criterion.*`, `PoseMeasurement.*`):

| Yêu cầu | Mục trong code | Nhóm |
|---|---|---|
| Máy nghiêng | `.ROLL` (`nghieng_ngang`) | Vị trí đặt máy |
| Máy cao/thấp | `.ELEVATION` (`cao_thap`) | Vị trí đặt máy |
| Máy ngửa/chúc | `.PITCH` (`ngua_chuc`) | Vị trí đặt máy |
| Khoảng cách & khung hình | `.SCALE` (`xa_gan`) + `.PERSPECTIVE` (`zoom_khoangcach`) | Một nhóm hiển thị, hai phép đo |
| Lệch trái/phải | `.CENTER` (`trai_phai`) | Vị trí đặt máy |
| Hướng mẫu | `.YAW` (`huong`) | Người mẫu |
| Dáng tay chân | `.POSE` (`dang`) | Người mẫu |

**Thứ tự khai báo trong `Criterion` = thứ tự kiểm.** Máy nghiêng (`ROLL`) đã được kéo xuống
cuối từ 12/09/2026 vì nhiễu tay người cầm làm nó bịt kín kênh hướng dẫn (`TemplateProfile.swift`,
chú thích dài phía trên enum). Giữ nguyên.

---

## 1. BẢNG QUYẾT ĐỊNH CÔNG NGHỆ (đọc nhanh)

| # | Mục | Nguồn dữ liệu iOS | Ảnh mẫu | Camera live | Đủ chưa | Nếu chưa → đổi sang |
|---|---|---|---|---|---|---|
| 1 | Máy nghiêng | `Vision` 2D (trục thân/vai) **+ `CoreMotion` chỉ để chọn ai bị nhắc** | 2D trên ảnh tĩnh | 2D trên khung + cảm biến để định lỗi | ✅ đo được | — (dấu cảm biến cần kiểm, không gấp) |
| 2 | Cao/thấp | `CoreMotion` (góc máy) + `AVFoundation` (vFOV) + `Vision` 2D (mốc y) | **NHÃN GÓC trong tên file** (`tren`/`ngang`/`duoi`) | cảm biến trọng lực `CMDeviceMotion.gravity` | ✅ | — |
| 3 | Ngửa/chúc | `CoreMotion` + 2D/3D (`Vision`) | nhãn góc (chính) / tỉ lệ chân-thân (phụ) | cảm biến (chính) / tỉ lệ chân-thân (phụ) | ✅ | — |
| 4 | Khoảng cách & khung hình | `Vision` 2D (cỡ mốc) + `Vision` 3D (mét) + `DistanceEstimator` | 3D mét + 2D | 3D mét + 2D + `videoZoomFactor` + `videoFieldOfView` | ✅ | — |
| 5 | Lệch trái/phải | `Vision` 2D (x của mốc) | 2D | 2D | ✅ | — |
| 6 | Hướng mẫu | `Vision` 3D `VNDetectHumanBodyPose3DRequest` (=17 khớp, mét) + `Vision` mặt `VNDetectFaceRectanglesRequest` | 3D / mặt | 3D / mặt | ✅ | ✅ đã chèn `VNDetectFaceRectanglesRequest` cho `VNFaceObservation.yaw` (iOS 11+) |
| 7 | Dáng tay chân | `Vision` 2D (góc khớp trên ảnh) + 3D để loại cánh tay chĩa vào máy | 2D | 2D | ✅ (chỉ dáng đứng) | — |

⚠️ Rủi ro nền chung: **Vision kém hơn MediaPipe với người quay lưng** (`FOOTGUNS`, `SO_SANH`).
Android đã chứng minh 280/280 khung không mất dấu khi mẫu xoay đủ vòng; bản iOS **chưa kiểm**.
Mục phải làm đầu tiên trong buổi đo (xem mục 9). YAW và POSE dựa trực tiếp vào đây.

---

## 2. MÁY NGHIÊNG — `.ROLL` (`nghieng_ngang`)

### Đo cái gì
Góc trục thân người so với phương thẳng đứng **của ảnh**, đơn vị **độ**.
`0` = dựng đứng, dương = thân nghiêng sang phải trong khung. `reference` = **25°** (lệch quá
mức này là ảnh hỏng hẳn).

### Công thức & hai đường đo (`Measurer.measureRoll`, `PoseMeasurement.RollSource`)
App giữ **bản đồ** hai đường, chỉ so 2 số **cùng đường** (`signedDelta` lặp theo thứ tự `SPINE` → `SHOULDERS`):

| Đường | Số đo | Vì sao mạnh / yếu | Bỏ khi |
|---|---|---|---|
| `SPINE` | `atan2(dx, dy)` của vector hông→cổ | dài, **không đổi khi mẫu xoay người** | thân co rút < 1× bề ngang vai (`THAN_TOI_THIEU_THEO_VAI` — chụp từ trên cao) |
| `SHOULDERS` | `atan2(dy,dx)` đường hai vai, **gấp về ±90°** | chỉ cần thấy vai (chân dung/bán thân) | vai chồng nhau (`span < MIN_SHOULDER_SPAN = 0.03`) |

⚠️ Đường vai **bắt buộc gấp về ±90°** — `LEFT/ RIGHT_SHOULDER` đặt theo GIẢI PHẪU của người
mẫu, mẫu quay mặt vào máy thì vai trái nằm bên phải ảnh (`atan2` ra ~180°). Đo trên 5 ảnh
`test-media/5-chan-dung-zoom/`: trục thân 0,5–2,8° còn vai 177–180°; trộn hai đường là sai
hoàn toàn (FOOTGUNS 39).

### Nguồn công nghệ — ⚠️ điểm quan trọng nhất
- **Ảnh mẫu và camera ĐỀU đo từ ẢNH** (2D Vision), không từ cảm biến. Tài liệu
  `PoseMeasurement.rollDeg` viết rõ lý do: ảnh mẫu là ảnh tĩnh, không có cảm biến; lấy cảm biến
  cho camera rồi trừ đi số suy từ ảnh mẫu là **phá bất biến "cùng một hàm"**, và vỡ ở ca thật:
  mẫu ngả người → máy vẫn thẳng → app đòi xoay máy thêm.
- **`CoreMotion` vẫn được dùng — nhưng chỉ để phân xử ai bị nhắc**: `GuidanceEngine`
  đọc `deviceRollDeg`; nếu máy vẹo ≥ `DEVICE_ROLL_BLAME_DEG = 3°` thì câu nhắc là câu cho người
  CẦM MÁY, ngược lại là câu cho người MẪU (đứng thẳng người lại). Chỉ tin cảm biến khi
  `|devicePitchDeg| < DEVICE_ROLL_TRUST_PITCH_DEG = 60°`.
- API iOS: `Vision.VNDetectHumanBodyPoseRequest` (2D ≈19 khớp) qua `VisionPose.swift`; cảm biến
  `CoreMotion.CMMotionManager.deviceMotion.gravity + rotationRate` qua `DeviceTilt.swift`.

### Ngưỡng (`GuidanceConfig`)
| | Giá trị | Xuất xứ |
|---|---|---|
| `accept` | **6,0°** | Nới từ 3,0° (12/09/2026): 3° đúng quy tắc 3σ (nhiễu tripod 0,92°) nhưng tay người tự vẹo 1–3° nên mục không bao giờ tự tắt; video thật ghi nó chiếm 7/9–9/11 khung |
| `enter` | 9° | `accept × 1,5` |
| `unlock` | 18° | `accept × 3` |
| `actionFloor` | 2° | dưới mức này xoay tay cũng không chỉnh nổi |
| `reference` | 25° | ảnh nghiêng quá mức này là hỏng |

Trạng thái: đã đo trên **ảnh thật** (σ trục thân 0,92°, vai 0,85°), **chưa đo tay cầm thật**
trong buổi đo tripod.

### Vấn đề còn mở / chuyển công nghệ
Không cần đổi công nghệ. Hai việc vặt trong buổi đo:
- Dấu `rollDeg` của `DeviceTilt` (công thức `atan2(-gx, gy)`) đúng chiều khi cầm máy thật chưa —
  ảnh hưởng nhỏ vì nó chỉ chọn lời nhắc, không chấm điểm; còn để tự nắn ảnh dưới 3° thì nắn
  sai chiều là xấu hơn không nắn (kiểm luôn).
- Nếu muốn "vẹo chân trời" tuyệt đối hơn, `CoreMotion` đo chính xác hơn hẳn ảnh — nhưng **không
  được** thay thế ảnh vì lý do bất biến ở trên.

---

## 3. MÁY CAO/THẤP — `.ELEVATION` (`cao_thap`)

### Đo cái gì
Góc nhìn từ máy tới mốc trên cơ thể, **đơn vị độ**. Âm = tia chúc xuống (máy CAO hơn mốc),
dương = máy THẤP hơn, 0 = ngang tầm. `reference` = **35°**. Trọng số cơ sở 2,5.

⚠️ **Khác** với mục 4: `ELEVATION` là **"máy cao hay thấp"**, còn `PITCH` (mục 4) là **"máy
ngửa hay chúc"**. Hai phương trình độc lập; cùng nhau xác định đủ cả độ cao lẫn độ chúc. Bản
cũ iOS đo "vị trí mốc trong khung" gọi là cao/thấp — sai, vì hai cách cầm máy khác hẳn cho cùng
vị trí mốc (video test: nhạy với khoảng cách 0,058 > nhạy với độ cao máy 0,041; FOOTGUNS 62).

### Công thức (một hàm dùng cho cả ảnh mẫu và camera — `Measurer.gocNhin`)
```
elevationDeg = tiltDeg + (0,5 − y_mốc) × vFOV
```
Ba số hạng:

| Số hạng | Ảnh mẫu | Camera live |
|---|---|---|
| `tiltDeg` | **NHÃN GÓC trong tên file** (`MediaLibrary.GocMayNhan`): `tren` = −35° · `ngang` = 0° · `duoi` = +25°. **Không suy từ ảnh** (xem mục 3.1) | **Cảm biến trọng lực**: `CMDeviceMotion.gravity`, lấy `sinPitch = −gz/|g|` sau khi đảo dấu cả 3 trục về quy ước TYPE_GRAVITY của Android — chính xác < 1°. Selfie thì đảo dấu (`mode.camTruoc ? -pitch : pitch`) |
| `y_mốc` | `elevationAnchorY` đo được lúc chốt hồ sơ ảnh mẫu | `Measurer.elevationAnchorY` của khung camera |
| `vFOV` (góc mở DỌC) | **Giả định** `Measurer.VFOV_ANH_MAU = 65°` (ống chính 4:3 ~26mm; 0/13 ảnh mẫu còn EXIF) | **Đọc từ phần cứng**: `AVCaptureDevice.Format.videoFieldOfView` (góc NGANG) quy về dọc: `tan(vFOV/2)/zoom`, nhân tỉ lệ khung khi ảnh mẫu rộng hơn cảm biến — `CaptureController.verticalFovDeg` |

Mốc `y_mốc` theo lớp khung hình (`FramingClass.elevationAnchor`, SUY MỘT LẦN từ ảnh mẫu):

| Lớp | Mốc |
|---|---|
| `.full` / `.knee` | ngang HÔNG (`midHip`) |
| `.half` | ngang THÂN (`midTorso`) |
| `.chest` / `.head` | ngang MẮT (`eyeLine`) |

**Chốt chặn:** `|0,5 − y| > MOC_LECH_TAM_TOI_DA = 0,15` thì **bỏ hẳn mục này** — số hạng vFOV
đoán (sai ±20°) lấm át phần đo: y lệch 0,263 cho sai 5,3° bằng cả ngưỡng đạt (6°).

### 3.1 Vì sao góc máy của ẢNH MẪU phải lấy NHÃN, không suy từ ảnh (đây là mục "công nghệ không giải quyết được" rồi phải đổi)
Đã thử 3 cách suy góc máy từ ảnh mẫu và **loại cả 3** (`DIEM_YEU_GOC_MAY_SELFIE.md`, cập nhật
16/09/2026, FOOTGUNS 91):
- Ảnh studio chụp thẳng đọc ra **+17°** — lẫn dáng đứng và loại ống kính.
- Selfie không suy được góc máy (mẫu tựa vào vị trí máy).
- Suy từ trục thân 3D lệch hệ thống (cầm thẳng đọc −14°..−23°; FOOTGUNS + `PoseMeasurement.tiltDeg`).

→ **Giải pháp đã đổi:** người dùng GÁN TAY góc máy bằng tên file 3 mức thô
(`tren/ngang/duoi`), `MediaLibrary.gocMayTheoNhan(name)` đọc ra độ. Cơ chế nhãn là **cùng một
đường code** cho ảnh cài sẵn lẫn ảnh tự nhập (ảnh tự nhập bắt buộc qua bước "gán nhãn" khi
chép vào thư viện). Không có nhãn → **bỏ mục 3 và mục 4**, không đoán bừa (`boGocMayTuAnh()`).

Đây chính là trường hợp "đổi công nghệ" của bạn đã được áp dụng: từ **suy luận hình học ảnh**
→ sang **nhãn thủ công (ảnh mẫu) + cảm biến (camera)**, cả hai đều không thêm dependency.

### Ngưỡng (`GuidanceConfig.theoLop`)
| | Giá trị | Xuất xứ |
|---|---|---|
| `accept` | **10,0°** (mọi lớp) | Nới rộng 14/09/2026: bảng v3 ghi 6/6/4/3° nhưng ảnh mẫu chỉ còn là nhãn thô (trên/ngang/dưới), sai số mốc cỡ 10°; tài liệu gốc chia góc máy 5 bậc chấp nhận "đúng bậc hoặc kề 1 bậc" ≈ ±12°. 10° vẫn tách được 3 kiểu: thẳng ~0°, chúc −35..−55°, ngửa +25..+40° |
| `enter` | 15° | `×1,5` |
| `unlock` | 30° | `×3` |
| `actionFloor` | 4° | nâng/hạ dưới mức này không ai thấy ảnh đổi |
| `reference` | 35° | — |

⚠️ Số `6.0°` trong `acceptFor` là **chết lối mòn** — `theoLop` trả 10° trước nên 6° không bao giờ
chạm tới. Không sửa kẻ nhầm sau này. Mục này **chưa đo máy thật** — chặn trên nhiễu đo từ 5 ảnh
(cùng góc, khác khoảng cách/zoom) là 6,3°.

### Vấn đề còn mở
- Cần buổi đo tripod chốt `accept` theo quy tắc 3σ.
- `Tren`/`ngang`/`duoi` là 3 mức thô — mức giữa 0°..−35° (ảnh tự nhập) vẫn dùng đúng số người
  gán, chấp nhận sai số; `GOC_GAT_DEG = 20°` (`TemplateProfile`) dùng để bỏ hẳn mục độ méo cho
  ảnh mẫu chụp gắt.

---

## 4. MÁY NGỬA/CHÚC — `.PITCH` (`ngua_chuc`)

### Đo cái gì
Độ ngẩng trục ống kính so với phương ngang. Âm = chúc xuống, dương = hất lên, 0 = ngang.
`reference` = **0,35** (⚠️ **chỉ số KHÔNG đơn vị**, không phải độ — nhưng đường chính nay đã ra
độ, xem dưới). Trọng số cơ sở 2,0.

### Hai đường đo — ⚠️ không so được với nhau (`PitchSource`, `signedDelta` lặp theo thứ tự `GOC_MAY` → `LEGS`)
| Đường | Thang | Ảnh mẫu | Camera | Bỏ khi |
|---|---|---|---|---|
| `GOC_MAY` (chính) | **ĐỘ** | **nhãn góc** (`tren/ngang/duoi`) hoặc bị xoá | **cảm biến trọng lực** (`DeviceTilt.cameraPitchDeg`) | ảnh mẫu không có nhãn → chỉ còn LEGS |
| `LEGS` (phụ) | tỉ lệ không đơn vị: `log((chân/thân trên ảnh)/(chân/thân ngoài đời))`, dương = chân dài ra = **hất lên** | 2D + 3D `worldLandmarks` | 2D + 3D | chân chĩa vào ống kính (`outOfPlaneDeg > 40°`) |

Hai đường lệch nhau **6,5×** về độ nhiễu (chân 0,016 – mặt 0,104 đo trên 19 ảnh) nên **bắt buộc**
ngưỡng riêng: trộn nguồn giữa ảnh mẫu và camera từng là lỗi "mỗi bên đúng, phép trừ vô nghĩa".

### Nguồn công nghệ
- Ảnh mẫu đường chính: `MediaLibrary.gocMayTheoNhan` — **nhãn 3 mức**, đúng như mục 3. Camera:
  `CMDeviceMotion.gravity` (đã đảo dấu trục, công thức `sinPitch = −gz/|g|`). Cả hai cùng thang
  độ → so trực tiếp. Trước 14/09/2026 camera suy từ trục thân 3D, lệch hệ thống −14°..−23° khi
  chụp thẳng — đã bỏ.
- Đường phụ `LEGS`: `World` quy ước mét gốc hông, gốc từ **`Vision.VNDetectHumanBodyPose3DRequest`**
  (17 khớp, `worldLandmarks`).

### Ngưỡng (`GuidanceConfig.bandFor`)
| Đường | `accept` | `enter` | `unlock` | `actionFloor` |
|---|---|---|---|---|
| `GOC_MAY` (độ) | **12,0°** (mọi lớp, nới 14/09/2026) | 18° | 36° | **3°** |
| `LEGS` (tỉ lệ) | **0,105** (`PITCH_LEGS_ACCEPT`) | 0,1575 | 0,315 | 0,06 |

- `PITCH_SPINE_ACCEPT_DEG = 5°` là di tích (khi đo bằng trục thân 3D) — giữ để đối chiếu lịch sử.
- `reference` 0,35 của mục này **mang đơn vị của đường phụ**; đường chính ra độ nên trong
  `ShotScorer` người ta quy theo nguồn.

Trạng thái: đường `LEGS` ngưỡng **đã đo trên ảnh thật** (accept ≥ 3×0,016 = 0,048, vậy 0,105 là an
toàn); đường `GOC_MAY` (cảm biến) **chưa đo tay cầm** — mục cần kiểm kỹ nhất trong buổi đo
(`reference` là con số phỏng đoán, `GuidanceConfig` ghi thẳng điều này).

### Vấn đề còn mở / chuyển công nghệ
- Vẫn là **sai số của NHÃN ảnh mẫu** (3 mức thô) chứ không phải của cảm biến — ngưỡng 12° vừa
  đủ rộng. Không cần đổi công nghệ.
- Nếu sau buổi đo muốn bỏ hẳn nhãn, phương án duy nhất iOS thuần: dùng `CoreMotion` ở hai bên
  (nhưng ảnh mẫu không có cảm biến) — **đã loại**. Nhãn là phương án cuối cùng, giữ.

---

## 5. KHOẢNG CÁCH & KHUNG HÌNH — `.SCALE` (`xa_gan`) + `.PERSPECTIVE` (`zoom_khoangcach`)

Hai **phép đo khác nhau** hiển thị thành **một nhóm** `groupLabel = "Khoảng cách & khung hình"`
để người dùng chỉ thấy một câu hỏi "đứng đủ xa chưa". Bên trong vẫn giữ hai mục riêng vì chúng
đo hai thứ khác nhau.

### 5.1 `.SCALE` — Xa/gần
**Đo:** chiều cao MỐC trong khung theo tỉ lệ chiều cao khung hình (`PoseMeasurement.scale`, 0..1
tỉ lệ). Lớn hơn = mẫu chiếm nhiều khung hơn = máy GẦN hơn. `reference` = **0,30**. Trọng số cơ sở
3,0.

Mốc theo lớp (`FramingClass.scaleAnchor`) — **bắt buộc cùng định nghĩa ở hai bên**:

| Lớp | Mốc `scale` | Mốc chiều cao THẬT (mét, cho `DistanceEstimator`) |
|---|---|---|
| `.full` | đỉnh đầu → cổ chân | nose → giữa cổ chân (`anchorHeightMeters`) |
| `.knee` | đỉnh đầu → gối | nose → giữa gối |
| `.half` | đỉnh đầu → hông | nose → giữa hông |
| `.chest` / `.head` | **khung mặt** (`faceHeight` từ `faceBox`) | **`nil`** — `worldLandmarks` không cho chiều cao mặt đáng tin, không đoán |

⚠️ Hai bẫy đã gặp: (a) chân chĩa vào ống kính thì `segmentUsable` (góc lệch mặt phẳng > 40°) bỏ
mốc — mẫu đá chân làm cổ chân tụt xuống → tưởng cao lên → tưởng máy gần; (b) `scale` là TỈ LỆ
của khung chứa nó → **phải cắt khung camera về đúng tỉ lệ ảnh mẫu** trước (`croppedToAspect` —
PO chốt "template vuông thì khung vuông").

**Khoảng cách thật** (chỉ để nói số bước — `DistanceEstimator`):
```
d = C × zoom × H_thật / s          với C = lensConstant 0,678 (hoặc 1/(2·tan(vFOV/2)) từ ống thật)
```
- `zoom` = `AVCaptureDevice.videoZoomFactor` trên đúng ống **`builtInWideAngleCamera`**
  (`CaptureController.cameraDevice`) — cố ý tránh `default(for:)` trả "virtual device" (ống kép)
  để `videoZoomFactor = 1` đúng là 1x, khớp thang của Android (SO_SANH #8 đã cảnh báo và code đã
  xử lý).
- `vFOV` từ `videoFieldOfView` (ngang → dọc, ÷ zoom, × tỉ lệ khung). Sai số đo 13 ảnh: trung bình
  16%, lớn nhất 39% — nên **chỉ đếm bước** (`stepsPhrase`), không bao giờ hiện số mét.
- Khoảng cách tối thiểu theo lớp (quyết định sản phẩm): head/chest 1,5m · half 2,0m · knee 2,5m ·
  full 3,0m.

**Ngưỡng `SCALE` (`theoLop`) — khung càng chặt càng siết:**
| | full/knee | half | chest | head |
|---|---|---|---|---|
| `accept` | 0,10 | 0,10 | 0,08 | 0,06 |
| `actionFloor` | 0,05 | 0,045 | 0,03 | 0,02 |
| `enter`/`unlock` | ×1,5 / ×3 | (giống) | | |

So theo **tỉ lệ tương đối** `|live − mẫu| / mẫu`. Trọng số theo lớp (`weightFor`): full/knee 0,16 ·
half 0,19 · chest/head **0,24** — cao nhất nhóm, đúng ý "chụp chân dung sai khoảng cách là hỏng".

### 5.2 `.PERSPECTIVE` — Zoom & khoảng cách (chỉ ảnh THẤY CHÂN)
**Đo:** độ mạnh phối cảnh **miễn nhiễm zoom**:
```
P = ln( (thân/chân TRÊN ẢNH) / (thân/chân NGOÀI ĐỜI) )   — cặp TORSO_ANKLE (mạnh), TORSO_KNEE (dự phòng)
```
Chia cho tỉ lệ "thật" (`worldLandmarks`) để khử khác biệt cơ thể giữa mẫu ảnh và mẫu thật (bỏ
bước này SNR tụt 4,67 → 2,68). Càng LỚN = máy càng gần. `reference` = 0,30. Trọng số cơ sở 1,5
(`weightFor` chỉ full/knee = 0,10).

Vì sao cần: `SCALE` một phương trình hai ẩn (`s = f·S/d`) — *đứng gần góc rộng* và *đứng xa
zoom vào* cho ra cùng `scale` nhưng ảnh khác hẳn. `P` chỉ phụ thuộc vị trí máy.

**Bật/tắt:** chỉ khi `framing.seesLegs` (full/knee) **VÀ** `|nhãn góc| < GOC_GAT_DEG = 20°`
(ảnh chụp từ trên cao làm chân co y như đứng gần → bỏ mục, FOOTGUNS 99). Ảnh cận: kể đúng lý do
cho người dùng và đưa **cả hai lựa chọn** (đi bộ hoặc zoom) — app không tự kiểm được zoom ở lớp đó.

**Ngưỡng (`acceptFor`):** `accept` = **0,10** (đo 13 ảnh thật: nhiễu σ 0,029/0,034 → 3σ 0,086/0,103;
lấy theo cặp yếu hơn vì tầng lệch không nói đã dùng cặp nào). `actionFloor` 0,05. Bắt được khác
biệt khoảng cách **từ ~2,5× trở lên**, không bắt ±30%.

**Logic realtime thêm (14/09/2026):** đã lùi đủ xa (`DistanceEstimator.estimate ≥ minStandoff`)
thì thôi bắt lùi (`deviation = 0`), tránh "lùi mãi không dừng".

### Nguồn công nghệ
`Vision` 2D cho tỉ lệ trên ảnh; `Vision 3D` (`worldLandmarks`, 17 khớp mét) cho tỉ lệ "thật";
`AVFoundation` cho zoom và vFOV; `DistanceEstimator` thuần toán. Giả định "mẫu cao 1m70" đã bỏ
từ lâu — chiều cao thật đọc từ `worldLandmarks` (`anchorHeightMeters`).

### Vấn đề còn mở / chuyển công nghệ
Không cần đổi. Hai điểm đo thật: `PERSPECTIVE` hiện có kiểm chứng ảnh thật tốt; phần `SCALE`
+ bước chân cần đo trên máy thật (ống kính khác C hơi khác — `heSoOngKinh` dùng vFOV thật để
giảm sai số). Nếu muốn chính xác hơn: `AVCaptureDevice.intrinsicMatrix` cho tiêu cự/cảm biến
chính xác thay vì `videoFieldOfView` — nhưng quyết định 04/09/2026 đã chốt **bỏ hướng đó** vì
phức tạp / máy khai báo sai.

---

## 6. LỆCH TRÁI/PHẢI — `.CENTER` (`trai_phai`)

### Đo cái gì
Vị trí NGANG của mốc, `0` = mép trái, `1` = mép phải khung. `reference` = **0,22**. Trọng số 2,5.
Mốc theo lớp (`FramingClass.centerAnchor`):

| Lớp | Mốc |
|---|---|
| `.full`/`.knee`/`.half` | giữa CỔ-HÔNG (`torsoCenter = (neck.x + root.x)/2`) |
| `.chest` | giữa HAI VAI (`shoulderCenter = neck.x`) |
| `.head` | giữa KHUNG MẶT (`faceCenter`) |

So `|live − mẫu|`. Trọng số theo lớp: full/knee 0,14 · half 0,15 · chest/head 0,18.

### Nguồn công nghệ
`Vision 2D` (19 khớp) trên khung **đã cắt về đúng tỉ lệ ảnh mẫu** (`croppedToAspect`) — không cắt
là so hai hệ quy chiếu khác nhau (ảnh mẫu vuông vs khung 9:16). Selfie gương: `mirrored()`
đảo `x → 1−x`, `x → −x` của `world`, và **hoán đổi nhãn trái/phải** (`Lm.mirrorIndex`) — thiếu bước
3 thì hình lật đúng mà mọi câu "ngả sang trái/phải" chỉ nhầm bên. Lưu ý lật ảnh gương làm **đảo
chiều** câu nhắc lệch trái/phải (xử lý ở `CuePresenter`).

### Ngưỡng (`theoLop`)
| | full/knee | half | chest | head |
|---|---|---|---|---|
| `accept` | 0,05 | 0,05 | 0,04 | 0,03 |
| `actionFloor` | 0,02 (mọi lớp) | | | |

Không có bẫy công nghệ đặc thù iOS. **Chưa đo máy thật** (số v3, cùng quy tắc 3σ).

---

## 7. HƯỚNG MẪU — `.YAW` (`huong`)

### Đo cái gì
Góc xoay quanh trục đứng, **độ**. `0` = mẫu quay thẳng mặt vào máy, ±180° = quay lưng.
`reference` = **55°**. Trọng số cơ sở **3,0 (cao nhất)**, theo lớp: full/knee 0,26 · half 0,24 ·
chest/head 0,22.

### Nguồn công nghệ — bản iOS đã thay đổi CĂN BẢN so với tài liệu cũ
- **Đường thân (`body3D`)**: `atan2(zL − zR, xL − xR)` trên `worldLandmarks` của
  `VNDetectHumanBodyPose3DRequest` (17 khớp, mét). `atan2` ổn định ở MỌI góc → **bỏ được** vùng
  chết 0,93, bỏ `r/rFront`, bỏ bộ lọc bù từng phiên mà tài liệu cũ (`NGUONG_VA_GOC_QUY_CHIEU`,
  `TONG_QUAN §8.2`) vẫn mô tả — đó là cách tính của bản iOS CŨ khi chỉ có 2D.
  ⚠️ Thứ tự hai vai quyết định gốc `0°` (l.−r. chứ không phải r.−l.); dấu trái/phải và trục z
  của Vision 3D **chưa xác nhận trên máy thật** — con số #4 trong buổi đo (`TONG_QUAN §10.3`).
- **Đường mặt (`faceYaw`)**: dùng cho `.chest`/`.head` (chính xác hơn ~3–5° so với 8–10° của
  thân). Android lấy từ ML Kit Face (`headEulerAngleY`).

### ✅ ĐÃ CHÈN CÔNG NGHỆ (10/10/2026) — mục này chạy được với ảnh chân dung
Trước đây iOS **không có bộ nhận diện khuôn mặt**: `PhanTichAnhMau.face` luôn `nil`, nên
`yawSource = .faceYaw` cho `.chest`/`.head` có cả hai bên `FaceInfo.yawDeg = nil` →
`signedDelta` trả `nil` → mục `YAW` mãi `UNMEASURED`, bị auto-mode bỏ qua. Đúng kiểu
"mục tưởng có mà chạy là tắt" mà dự án cấm.

**→ ĐÃ chèn `Vision.VNDetectFaceRectanglesRequest`** (framework hệ điều hành, không thêm
dependency, đúng 1-1 với bảng ánh xạ `TONG_QUAN §8.1`: `VNFaceObservation.yaw` ↔
`headEulerAngleY`). File mới `face/FaceAnalyzer.swift` lấy `VNFaceObservation.yaw`
(radian, ±π/2 ≈ ±90°) → quy đổi độ → `FaceInfo.yawDeg`. Đã ghép vào 4 chỗ:

1. `home/PhanTichAnhMau.swift` — chạy face request **sau khi ảnh qua cổng kiểm** → `face`.
2. `capture/CaptureScreen.swift` (`phanTichAnhMau()`) — ảnh mẫu của màn chụp cũng đi qua
   `FaceAnalyzer` để hồ sơ tiêu chí có góc mặt.
3. `capture/CaptureScreen.swift` (`batMay()`) — callback `onFrameImage` của `PoseDetector`
   chạy `FaceAnalyzer` trên khung có người, khoá tần suất ~300ms (`FaceThrottle`) →
   `vm.onLiveFace`.
4. `capture/CaptureScreen.swift` (`xuLyVideo`/`xuLyBurst`) — truyền
   `faceAnalyze: { FaceAnalyzer.face(from: $0) }` cho `ShotSession` để chấm hậu kỳ cũng có
   góc mặt.

`PoseDetector` đã được sửa để **chỉ dựng ảnh khung khi thật có người** (`!frame.isEmpty`) —
đúng như chú thích cũ, tránh chuyển pixel buffer vô ích.

⚠️ **Còn phải kiểm trên máy thật** (mốc #4 của buổi đo): dấu của `VNFaceObservation.yaw`.
Không chặn mục chạy vì `yawDeviation` so bằng `angleDiff` (độ lệch tuyệt đối, không phân
biệt trái/phải — `ShotScore`), chỉ cần hai bên cùng thang — và chúng cùng thang vì cùng
một request. `eyesOpen` (mục hậu kỳ `EYES_OPEN`, trọng số 0,06) **vẫn `nil` trên iOS**:
`VNDetectFaceRectanglesRequest` không đo độ mở mắt, `TemplateProfile` tự bỏ và ghi lý do.

Phương án dự phòng nếu ảnh mặt hỏng nhiều (chưa cần): trỏ `yawSource` về `body3D` cho cả 5
lớp (chỉ cần vai, không cần hông).

### Ngưỡng (`theoLop`)
| | full/knee | half | chest | head |
|---|---|---|---|---|
| `accept` | 30° | 30° | 20° | 15° |
| `actionFloor` | 15° (mọi lớp) | | | |

Rộng vì đường thân sai số 8–10°; siết khi có face vì mặt chính xác hơn. **Chưa đo máy thật.**
Trong `signedDelta` góc được quy về ±180° để trừ đúng (`while d > 180`).

### Vấn đề còn mở
- Rủi ro **người quay lưng**: Vision kém hơn MediaPipe (mục 9 — ưu tiên số 1 của buổi đo).
- Dấu z / dấu trái-phải của Vision 3D chưa kiểm — nếu đảo, chỉ cần đổi cặp trong `VisionPose.put`
  hoặc đảo thứ tự hai vai trong `bodyYawDeg`.

---

## 8. DÁNG TAY CHÂN — `.POSE` (`dang`)

### Đo cái gì
Một bộ góc khớp, so trung bình lệch giữa mẫu và khung. `reference` = **55°**, trọng số cơ sở **1,0
(nhẹ nhất — không bao giờ chặn việc chụp)**. Đo trên toạ độ **2D của ẢNH**, cố ý: app khớp "trông
giống bức ảnh mẫu", không khớp tư thế trong không gian thật. Chỉ chấm nhóm khớp thuộc lớp khung
hình (`FramingClass.poseGroups`):

| Lớp | Nhóm khớp |
|---|---|
| `.full` | thân, đầu, tay, chân |
| `.knee` / `.half` | thân, đầu, tay |
| `.chest` | đầu, tay |
| `.head` | đầu |

Khớp nào không đo được → **NaN**, vắng mặt khỏi bộ so sánh — không bao giờ điền `0`
(vắng = "chưa đo được" = bỏ ra; `0` = "đo được và bằng 0" = chấm sai).

### Công thức & bẫy selfie
- Góc khớp: `jointAngle` (khuỷu/gối, 0..180°) qua `acos` chuẩn hoá; `segmentAngle` (thân/đầu).
- Tay: mảng **luôn đủ 4 phần tử** (2 góc khớp + 2 góc cánh tay), NaN cho ô không đo được — nhờ
  đó che một cổ tay không làm mất cả nhóm tay của bên kia (lỗi cũ `listOfNotNull`).
- **`armUsable`** — sinh ra cho selfie: tay cầm máy luôn chĩa vào ống kính (ràng buộc vật lý,
  không phải lựa chọn dáng). Dùng `worldLandmarks` đo góc "chĩa ra khỏi mặt phẳng ảnh"
  (`tilt(S,E)`, `tilt(E,W)`), nếu > `MAX_OUT_OF_PLANE_DEG = 40°` thì cánh tay đó bị loại khỏi
  mục dáng — nếu không app mãi báo "dáng tay chưa khớp" cho một dáng không ai đổi được. Luật này
  còn lọc cả ảnh phá cách chìa tay ra máy.

### Ngưỡng (`acceptFor`)
`accept` = **15°** (tài liệu v3: 15° cho khớp tay/chân; trung bình lệch góc các khớp),
`actionFloor` = 12°, `enter` 22,5°, `unlock` 45°. **Chưa đo máy thật.**

### Vấn đề còn mở / chuyển công nghệ
- `Vision` thiếu ngón tay/gót/mũi chân — **không sao**: app chỉ cần vai/khuỷu/cổ tay/hông/gối/cổ
  chân, toàn bộ đều có.
- Chỉ hỗ trợ **dáng đứng** (đã chốt scope).
- Cần kiểm dấu trái/phải nhãn khớp trên máy thật (giơ tay trái mà app đọc tay phải → đổi cặp
  `VisionPose.put`), và kiểm người quay lưng (như trên).

---

## 9. RÀ SOÁT TÀI LIỆU ĐÃ CÓ — cái nào CŨ, cái nào vẫn đúng

| Tài liệu | Kết luận sau rà soát |
|---|---|
| `SO_SANH_CONG_NGHE_ANDROID_IOS.md` | 🔴 **LỖI THỜI.** Khuyến nghị "dùng MediaPipe trên iOS luôn". Thực tế MediaPipeTasksVision 1.0.0 **sập trên iOS 27** (`AGXA13FamilyFunctionHandle resourceIndex` — pipeline Metal riêng) → đã đổi sang **Apple Vision** (commit `3d987c7`). Đây CHÍNH LÀ "ưu tiên package có sẵn của iOS". Cảnh báo #8 (zoom) và #9 (vFOV) đã xử lý trong code (`CaptureController`). Các rủi ro còn nguyên: "Vision kém với người quay lưng", "ngưỡng phải đo lại". → **Cần cập nhật lại mục 1, 3 và "Cần chốt trước khi code".** |
| `posecoach/DIEM_YEU_GOC_MAY_SELFIE.md` | ✅ Vẫn đúng. Nguồn của quyết định **nhãn góc 3 mức** (đã áp dụng: `MediaLibrary.GocMayNhan`, `tren −35 / ngang 0 / duoi +25`). |
| `posecoach/THAY_DOI_NHANH_THUAT_TOAN.md` | ✅ Vẫn đúng + đã có trong code: phân biệt "cao/thấp" (elevel) với "ngửa/chúc" (pitch); câu gộp `gopCaoVaChuc` (nâng+và-chúc / hạ+và-hất). |
| `posecoach/NGUONG_VA_GOC_QUY_CHIEU.md` | ✅ Nguồn ngưỡng v3. Bảng yaw "r/rFront + vùng chết 0,93" **không còn áp dụng** cho iOS: 3D Vision thay bằng `atan2` (`PoseGeometry.bodyYawDeg`) — bỏ vùng chết, bỏ `rFront`. |
| `posecoach/FOOTGUNS.md` | ✅ Nguồn các bẫy: tên trái/phải theo giải phẫu (39), nhãn góc (91), ảnh chụp từ trên cao bỏ độ méo (99), `MediaPipe` mất dấu người quay lưng (ở `FOOTGUNS`/`TONG_QUAN`). Đã áp dụng hết trong code iOS. |
| `posecoach/TONG_QUAN_DU_AN.md` | ✅ Khung chuẩn. §8.1 đã liệt kê đúng ánh xạ iOS (kể cả `VNFaceObservation.yaw` — đang là lỗ hổng chưa ghép, mục 7). Tài liệu này vẫn coi `legacy-ios/` là tham chiếu; code Swift trong `myposecoach1/` đã đi xa hơn (Vision + nhãn + 3D yaw). |

### Trạng thái đo đạc theo mục (để biết buổi đo còn thiếu gì)
| Mục | Đã đo ảnh thật | Chưa đo máy thật |
|---|---|---|
| Máy nghiêng `ROLL` | ✅ 5 ảnh (σ 0,92°) → 6° | tay cầm, dấu cảm biến |
| Cao/thấp `ELEVATION` | — | ✅ (10°) |
| Ngửa/chúc `PITCH` | ✅ đường LEGS (σ 0,016) | ✅ đường GOC_MAY (12°) |
| Xa/gần `SCALE` + khoảng cách | ✅ 13 ảnh (sai số 16%) | ✅ ống kính thật, bước chân |
| Zoom phối cảnh `PERSPECTIVE` | ✅ 13 ảnh (SNR 4,67) | triển khai trên camera thật |
| Lệch trái/phải `CENTER` | — | ✅ |
| Hướng mẫu `YAW` | ✅ nhãn tên vai (góc ~35° đọc −35,2°) | ✅ dấu z/trái-phải 3D; ✅ đã chèn `VNDetectFaceRectanglesRequest` cho chest/head (cần kiểm dấu `VNFaceObservation.yaw`) |
| Dáng `POSE` | — | ✅ (15°) + dấu trái/phải khớp |

### Ưu tiên buổi đo (đúng luật "accept ≥ 3σ, người đứng yên 20s, cả 5 lớp khung hình")
1. **Người quay lưng giữ dấu được bao lâu với Vision** (quyết định nhóm template quay lưng còn
   trong scope không — số quan trọng nhất, `TONG_QUAN §10.3`).
2. `YAW` 3D: dấu trái/phải + dấu z; sau khi chèn face, độ chính xác mặt so với thân.
3. `PITCH GOC_MAY` + `ELEVATION`: tay cầm thật dao động bao nhiêu (đang là 2 mục rộng nhất).
4. `ROLL` tay cầm (6° có tự tắt không), dấu `DeviceTilt.rollDeg`.
5. `SCALE`/`PERSPECTIVE`/`CENTER`/`POSE` theo bảng trên, kèm trọng số `Criterion.reference`
   đối chiếu (reference ≠ accept, không trộn).

---

## Phụ lục — Bản đồ file iOS (nơi sửa khi cần)

| Mảng | File | Ghi chú |
|---|---|---|
| Nhận diện (thay MediaPipe) | `pose/VisionPose.swift` | 2D ≈19 khớp + 3D 17 khớp (`include3D = true`); lật y một lần; nhãn trái/phải cần kiểm |
| Hệ toạ độ (bất biến) | `pose/PoseGeometry.swift` | `P2`/`P3`/`Lm`/`PoseFrame`; gốc trái-trên, y xuống |
| Lớp khung hình | `pose/FramingClass.swift` | 5 lớp + mốc đo + `yawSource` (faceYaw chưa có dữ liệu trên iOS) |
| Tầng đo "một hàm" | `measure/PoseMeasurement.swift` | `Measurer.measure` + `gocNhin` + `measureRoll/PitchCue/Perspective/Pose` |
| Ngưỡng (sửa DUY NHẤT ở đây) | `guidance/GuidanceConfig.swift` | `Band` 3 mức + `theoLop` + `acceptFor` |
| Engine + cảm biến | `guidance/GuidanceEngine.swift` · `sensors/DeviceTilt.swift` | gộp câu, đóng băng, `deviceRollDeg`/`devicePitchDeg` |
| Camera/phần cứng | `camera/CaptureController.swift` | `videoZoomFactor`, `verticalFovDeg`, hướng máy, mirroring |
| Khoảng cách (số bước) | `guidance/DistanceEstimator.swift` | `lensConstant`, `minStandoff`, `stepsPhrase` |
| Nhãn góc ảnh mẫu | `media/MediaLibrary.swift` | `GocMayNhan` (tren −35 / ngang 0 / duoi +25) + `KieuChupTren` |
| Hồ sơ tiêu chí | `template/TemplateProfile.swift` | mục nào áp dụng / bỏ / vì sao; `gocMayNhan`, `gocGat` |
| Face — mới thêm | `face/FaceAnalyzer.swift` | `VNDetectFaceRectanglesRequest` → `FaceInfo.yawDeg` (eyesOpen để nil; `FaceThrottle` khoá 300ms cho camera live) |