# MediaPipe compatibility spike

Status: source prepared; **not built or executed on iPhone yet**. No claim of iOS 27 compatibility or Android accuracy parity.

Independent app, with MediaPipe 1.1.0 pinned to `821db8a4428baf58bf4c09a0330c937e6e0a3753`. CPU, one pose, confidence thresholds 0.5, segmentation disabled. Model and bundled reference image are copied byte-for-byte from the frozen Android working tree. The production app remains on its existing implementation.

## Build on a Mac

1. Install Xcode with support for the device OS and XcodeGen (`brew install xcodegen`).
2. In this directory run `xcodegen generate`.
3. Open `MediaPipeIOS27.xcodeproj`, select your signing team and a physical iPhone.
4. Resolve Swift packages and build. Record Xcode version, OS build and device model with the test results. Treat compilation failures as a failed preparation check, not a runtime compatibility result.

## Run in order

1. Initialize: run from a fresh launch ten times. A native crash cannot be caught by Swift. The JSONL file flushes `init_begin` before initialization; retrieve it from the app container and collect the `.ips` crash report through Xcode Devices and Simulators.
2. Bundled Android image: export JSONL. Inspect pose count and 33 normalized/world points, including confidence. Empty detections are recorded, not interpreted as success for accuracy.
3. Video: select a short portrait clip with a visible person. Frames are decoded sequentially to BGRA with the track transform applied; timestamps come from the asset. Export results. Video import currently loads the file into memory, so use small fixtures.
4. Camera: hold the phone in portrait, point the rear camera at a person for 15 seconds. One pending inference maximum, no mirrored buffers. Export results; repeat after background/foreground and a cold launch.

Each export includes device, OS, mode, initialization events, full pose coordinates, timestamps and latency. A `complete` event means the run ended, **not** that parity passed. Camera reports pending callback count; nonzero requires investigation. The spike uses a fixed portrait rear camera contract; front camera, rotation, interruptions, long thermal tests and production capture are subsequent work.

Compatibility gate: no crash or inference errors in all modes on the reported iOS 27/device combinations. Accuracy gate separately requires the same images/video on Android with the same orientation/crop, comparison of landmarks and downstream cues, and explicit acceptance thresholds. One bundled image is a smoke fixture, not a representative evaluation set. Do not replace production Vision based only on smoke results.

## Sources

- [Official iOS setup](https://developers.google.com/edge/mediapipe/solutions/setup_ios)
- [Pose Landmarker iOS guide](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/ios)
- [Pinned API options and callback signature](https://github.com/google-ai-edge/mediapipe/blob/821db8a4428baf58bf4c09a0330c937e6e0a3753/mediapipe/tasks/ios/vision/pose_landmarker/sources/MPPPoseLandmarkerOptions.h)
