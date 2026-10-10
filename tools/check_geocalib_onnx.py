"""Smoke-run the frozen GeoCalib model and verify the iOS output contract."""
import sys
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort

root = Path(__file__).resolve().parents[1]
model = root / 'myposecoach1/myposecoach1/geocalib/geocalib-mang-int8.onnx'
image = root / 'myposecoach1/myposecoach1/templates/ngang-di-bo-ben-ho.jpg'
rgb = cv2.cvtColor(cv2.imread(str(image)), cv2.COLOR_BGR2RGB).astype(np.float32) / 255
h0, w0 = rgb.shape[:2]
scale = 320 / min(h0, w0)
h1, w1 = round(h0 * scale), round(w0 * scale)
small = cv2.resize(rgb, (w1, h1), interpolation=cv2.INTER_AREA)
h, w = (h1 // 32) * 32, (w1 // 32) * 32
y, x = (h1 - h) // 2, (w1 - w) // 2
chw = small[y:y+h, x:x+w].transpose(2, 0, 1)[None].astype(np.float32)

session = ort.InferenceSession(str(model), providers=['CPUExecutionProvider'])
assert [i.name for i in session.get_inputs()] == ['image']
assert [o.name for o in session.get_outputs()] == [
    'up_field', 'up_confidence', 'latitude_field', 'latitude_confidence'
]
outputs = session.run(None, {'image': chw})
expected = [(1, 2, h, w), (1, h, w), (1, 1, h, w), (1, h, w)]
assert [o.shape for o in outputs] == expected, ([o.shape for o in outputs], expected)
assert all(np.isfinite(o).all() for o in outputs)
print(f'PASS: GeoCalib input {chw.shape}, outputs {[o.shape for o in outputs]}')
