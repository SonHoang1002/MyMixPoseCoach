"""Static checks runnable on Windows before the required Xcode/device tests."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'baselines/android-2026-10-10/manifest.json').read_text(encoding='utf-8'))

checks = {
    'pose': (
        ROOT / 'myposecoach1/myposecoach1/pose_landmarker_full.task',
        'app/app/src/main/assets/pose_landmarker_full.task',
    ),
    'geocalib': (
        ROOT / 'myposecoach1/myposecoach1/geocalib/geocalib-mang-int8.onnx',
        'app/app/src/main/assets/geocalib/geocalib-mang-int8.onnx',
    ),
}
for label, (path, android_name) in checks.items():
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    expected = manifest['files'][android_name]['sha256']
    assert actual == expected, f'{label} model differs: {actual} != {expected}'

project = (ROOT / 'myposecoach1/myposecoach1.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
podfile = (ROOT / 'myposecoach1/Podfile').read_text(encoding='utf-8')
assert '821db8a4428baf58bf4c09a0330c937e6e0a3753' in project
assert 'b7fb7f7dea8a2469e6335d95a61b8f36d0dc83b2' in project
assert "GoogleMLKit/FaceDetection', '8.0.0'" in podfile
assert "GoogleMLKit/ImageLabeling', '8.0.0'" in podfile

pose_files = [
    ROOT / 'myposecoach1/myposecoach1/pose/PoseDetector.swift',
    ROOT / 'myposecoach1/myposecoach1/pose/StillPoseAnalyzer.swift',
    ROOT / 'myposecoach1/myposecoach1/pose/VideoPoseAnalyzer.swift',
]
assert all('MediaPipePose' in p.read_text(encoding='utf-8') for p in pose_files)
print('PASS: Android model hashes, dependency pins, and all three MediaPipe paths')
