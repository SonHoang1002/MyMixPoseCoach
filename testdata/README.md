# Local Pinterest test dataset

The generated image set lives at `testdata/pinterest-posecoach/` and is excluded
from Git. Each accepted image has exactly one usable MediaPipe pose, a minimum
short side of 480 px, and no close perceptual duplicate in the set or in the
current app templates. Its `manifest.csv` row records the public Pinterest pin,
direct image URL, intended photo type, gender search segment and camera angle.

Run from the repository root with the shared Python 3.10 environment:

```powershell
& 'D:\PROJECTS\Pj-demo\tools\goc-may\_ket-qua\moi-truong\Scripts\python.exe' `
  tools\download_pinterest_test_dataset.py
```

On another machine, create a Python 3.10 virtual environment and install the
small collector dependency set first:

```powershell
py -3.10 -m venv .venv-pinterest
.\.venv-pinterest\Scripts\python.exe -m pip install -r tools\requirements-pinterest-dataset.txt
.\.venv-pinterest\Scripts\python.exe tools\download_pinterest_test_dataset.py
```

The default target is 100 images for each app photo type: `photographer`,
`selfie`, and `mirror`. The command resumes an interrupted download. Use
`--fresh` to rebuild the generated directory, or `--limit-per-category 2` for a
small smoke test.

Pinterest images remain third-party material. Use this local set only for
internal app testing. Do not add the images to the app bundle, publish them, or
redistribute them without permission from their rights holders.
