# iOS ↔ Android parity status

Android source of truth: local `phuong-an-tich-hop` working tree frozen at commit `5993ab38a0dcac0c77c7835b5b8bf010052deb57`, including its uncommitted changes.

## Implemented in source

- MediaPipe Pose Landmarker 1.1.0 pinned by revision, CPU, Full model, one pose, thresholds 0.5 and segmentation off.
- One MediaPipe result conversion for image, tracked video and live camera paths; Apple Vision remains a crash-loop fallback.
- Pose model matches Android SHA-256 `4eaa5eb7a98365221087693fcc286334cf0858e2eb6e15b506aa4a7ecdcec4ad`.
- ML Kit Face Detection and Image Labeling 8.0.0 declared through CocoaPods. Face yaw and eye-open classification follow Android settings.
- GeoCalib ONNX Runtime 1.24.2 CPU path, matching preprocessing and the ported perspective solver.
- GeoCalib model matches Android SHA-256 `7e63366ef8b9acbe4a2350633d415015c5f4143fc9605057d5ca4734c73a5814`.
- Imported-image prediction uses ML Kit labels, missing wrists, GeoCalib pitch/VFOV and head-to-feet perspective. Certain results enter capture directly; uncertain answers remain editable.

## Required validation on macOS/iPhone

Source preparation on Windows cannot prove compilation, native compatibility, camera orientation or numerical parity. On a Mac run `./myposecoach1/typecheck.sh`, then execute the isolated spike and production app on physical iOS 27 devices. Compare the same Android/iOS fixture media before removing the Apple Vision fallback.

Remaining product parity after that gate: scene recommendation flow, full English/Vietnamese string catalog and settings UI, then measured performance/thermal tuning. KMP sharing should follow verified numerical parity; introducing it before that point would make native integration failures harder to isolate.
