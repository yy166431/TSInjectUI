# TSInjectUI (GitHub Actions ready)

- TrollStore-friendly dylib (no Substrate/libhooker)
- Shows "注入成功" alert
- Draggable floating ON/OFF button (remembers state & position)

## Build on GitHub
This repo includes `.github/workflows/build.yml`.
Go to **Actions** → select workflow → **Run workflow**.
Then download artifacts (deb + dylib/zip if present).

## Notes
- If you want to inject into another app, change BundleID in `tsinjectui.plist`
  and process name in `Makefile` (`INSTALL_TARGET_PROCESSES`).
