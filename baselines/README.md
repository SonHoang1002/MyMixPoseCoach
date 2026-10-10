# Android source of truth

`android-2026-10-10/manifest.json` records the Android `phuong-an-tich-hop` working tree at commit `5993ab38a0dcac0c77c7835b5b8bf010052deb57`, **including uncommitted files**. Per-file SHA-256 hashes identify the actual baseline. The local ignored `source.zip` contains 413 selected source, test, configuration, documentation and asset files. This is a source snapshot, not a complete Git repository backup. Build outputs, machine settings and keystores are excluded.

Recreate a new dated baseline with `python tools/freeze_android_baseline.py <android-repository> <new-output-directory>`. Do not overwrite this baseline after Android changes. Keep the local archive when moving to a Mac; the manifest alone cannot restore source. The spike resources must match the manifest entries for `app/app/src/main/assets/pose_landmarker_full.task` and `app/app/src/main/assets/templates/ngang-di-bo-ben-ho.jpg`.
