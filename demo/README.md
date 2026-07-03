# Look App Store Simulator Screenshots

App Store screenshots are captured from the **real app** talking to a **real
Look server**, seeded with generated landscape photography — not from demo
mocks. The images are procedurally generated (sunsets, mountain layers, aurora,
night skies, dunes…), so there are no licensing concerns.

## Capture

```bash
# 1. Start a seeded server (fresh DB + 36 generated photos + albums/tags/favorites)
OUT=/tmp/look-screenshot-library
rm -f /tmp/look-screens.db*
PORT=8765 PHOTO_DIR=$OUT DB_PATH=/tmp/look-screens.db \
  ./.conda/bin/python -m uvicorn api.server:app --host 127.0.0.1 --port 8765 &
./.conda/bin/python demo/generate_screenshot_library.py $OUT \
  --seed http://127.0.0.1:8765 /tmp/look-screens.db

# 2. Capture both devices
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ./demo/capture_app_store_screenshots.sh
```

The script builds the iOS app, boots an iPhone 13 Pro Max and an iPad Pro
13-inch simulator, and drives the app to each screen with DEBUG-only launch
environment variables (`LOOK_UI_TAB`, `LOOK_UI_ROUTE`, `LOOK_UI_SELECT_COUNT`,
`LOOK_UI_SEARCH_QUERY`, `LOOK_UI_SERVER_URL`, `LOOK_UI_CONNECTED` — see
`LookUIScreenshotRoute` in `ios/Look/ContentView.swift`), then captures with
`xcrun simctl io screenshot`.

Generated upload candidates are written to:

```text
demo/app_store_screenshots/iphone_6_7/
demo/app_store_screenshots/ipad_13/
```

The contact sheets below are only for review and are not intended for App Store
upload:

```text
demo/contact_sheet_iphone_6_7.png
demo/contact_sheet_ipad_13.png
```

The default devices target App Store Connect-compatible upload sizes:
`1284 x 2778` for iPhone and `2064 x 2752` for iPad 13-inch.

## Screens captured

01 connection setup · 02 gallery · 03 full-screen viewer · 04 multi-select ·
05 photo detail · 06 library · 07 search · 08 settings

## Legacy demo mode

`--look-demo-screenshots` (DemoScreenshotHost) still exists for quick,
server-free previews of individual screens, but it is no longer the App Store
pipeline.

## Privacy

The screenshot library is fully synthetic: generated images plus synthetic
EXIF (camera names, dates, a few landmark GPS coordinates). Nothing is read
from a personal photo library.
