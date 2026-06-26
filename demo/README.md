# Look App Store Simulator Screenshots

This folder is for App Store screenshot capture using the real iOS Simulator
and debug-only mock data.

## Capture

```bash
./demo/capture_app_store_screenshots.sh
```

The script builds the iOS app for the simulator, boots an iPhone 13 Pro Max
and an iPad Pro 13-inch simulator, launches Look with
`--look-demo-screenshots`, and captures each workflow screen with
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

## Privacy

The debug screenshot mode seeds the app with synthetic metadata and generated
thumbnail art. It does not connect to the Look server and does not read the
local photo library.
