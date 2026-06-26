#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT/ios"
BASE_OUT_DIR="$ROOT/demo/app_store_screenshots"
DERIVED_DATA="$IOS_DIR/build/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Look.app"
BUNDLE_ID="com.sladebot.look"
IPHONE_DEVICE_NAME="${LOOK_SCREENSHOT_IPHONE_DEVICE:-iPhone 13 Pro Max}"
IPAD_DEVICE_NAME="${LOOK_SCREENSHOT_IPAD_DEVICE:-iPad Pro 13-inch (M5)}"
SETTLE_SECONDS="${LOOK_SCREENSHOT_SETTLE_SECONDS:-3}"

SCENARIOS=(
  "connection:01_tailnet_connection.png"
  "sync:02_sync_progress.png"
  "gallery:03_main_gallery.png"
  "multiselect:04_long_press_multiselect.png"
  "detail:05_photo_detail_tags.png"
  "library:06_library_albums.png"
  "search:07_search_mock_library.png"
  "settings:08_settings_tailnet.png"
)

device_id_for_name() {
  python3 - "$1" <<'PY'
import json
import subprocess
import sys

name = sys.argv[1]
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
for runtime in data.get("devices", {}).values():
    for device in runtime:
        if device.get("name") == name:
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit(f"No available simulator named {name!r}")
PY
}

echo "[look-demo] Building Look for iOS Simulator"
xcodebuild build \
  -project "$IOS_DIR/Look.xcodeproj" \
  -scheme Look \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=$IPHONE_DEVICE_NAME" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO >/tmp/look-demo-xcodebuild.log

if [[ ! -d "$APP_PATH" ]]; then
  echo "[look-demo] App bundle not found: $APP_PATH" >&2
  exit 1
fi

capture_device() {
  local device_name="$1"
  local output_slug="$2"
  local contact_sheet="$3"
  local out_dir="$BASE_OUT_DIR/$output_slug"
  local device_id

  mkdir -p "$out_dir"
  rm -f "$out_dir"/*.png "$contact_sheet"

  device_id="$(device_id_for_name "$device_name")"

  echo "[look-demo] Booting $device_name ($device_id)"
  xcrun simctl boot "$device_id" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$device_id" -b >/dev/null
  xcrun simctl install "$device_id" "$APP_PATH"

  xcrun simctl status_bar "$device_id" override \
    --time 9:41 \
    --dataNetwork wifi \
    --wifiBars 3 \
    --cellularBars 4 \
    --batteryState charged \
    --batteryLevel 58 >/dev/null 2>&1 || true

  for entry in "${SCENARIOS[@]}"; do
    scenario="${entry%%:*}"
    filename="${entry#*:}"
    echo "[look-demo] Capturing $output_slug/$filename"
    xcrun simctl terminate "$device_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
    SIMCTL_CHILD_LOOK_DEMO_SCREEN="$scenario" xcrun simctl launch \
      --terminate-running-process \
      "$device_id" \
      "$BUNDLE_ID" \
      --look-demo-screenshots >/dev/null
    sleep "$SETTLE_SECONDS"
    xcrun simctl io "$device_id" screenshot "$out_dir/$filename" >/dev/null
  done

  python3 - "$out_dir" "$contact_sheet" "$output_slug" <<'PY'
from pathlib import Path
import sys
from PIL import Image, ImageDraw

out = Path(sys.argv[1])
sheet_path = Path(sys.argv[2])
label = sys.argv[3]
files = sorted(out.glob("*.png"))
for path in files:
    image = Image.open(path)
    if image.mode != "RGB":
        image.convert("RGB").save(path)
        image = Image.open(path)
    print(f"{path.name}: {image.size} {image.mode}")

thumbs = []
for path in files:
    image = Image.open(path).convert("RGB")
    image.thumbnail((260, 565))
    canvas = Image.new("RGB", (286, 630), (14, 16, 18))
    canvas.paste(image, ((286 - image.width) // 2, 12))
    draw = ImageDraw.Draw(canvas)
    draw.text((14, 594), path.name, fill=(238, 243, 246))
    thumbs.append(canvas)

cols = 4
rows = (len(thumbs) + cols - 1) // cols
sheet = Image.new("RGB", (286 * cols, 630 * rows), (14, 16, 18))
for index, thumb in enumerate(thumbs):
    sheet.paste(thumb, ((index % cols) * 286, (index // cols) * 630))
sheet.save(sheet_path)
print(f"{label} contact sheet: {sheet_path}")
PY

  echo "[look-demo] Screenshots written to $out_dir"
}

capture_device "$IPHONE_DEVICE_NAME" "iphone_6_7" "$ROOT/demo/contact_sheet_iphone_6_7.png"
capture_device "$IPAD_DEVICE_NAME" "ipad_13" "$ROOT/demo/contact_sheet_ipad_13.png"
