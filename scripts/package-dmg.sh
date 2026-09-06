#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_METADATA_KEYS_FILE="$PROJECT_DIR/Config/MetadataKeys.plist"
METADATA_KEYS_SOURCE="${METADATA_KEYS_FILE:-$DEFAULT_METADATA_KEYS_FILE}"
"$PROJECT_DIR/scripts/validate-metadata-keys.sh" "$METADATA_KEYS_SOURCE"
APP_PATH="$(
  METADATA_KEYS_FILE="$METADATA_KEYS_SOURCE" \
    REQUIRE_METADATA_KEYS=1 \
    "$PROJECT_DIR/scripts/build-app.sh" \
    | tail -n 1
)"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")"
OUTPUT_DIR="$PROJECT_DIR/dist"
DMG_PATH="$OUTPUT_DIR/TorrServer-$VERSION-macOS-arm64.dmg"
VOLUME_NAME="TorrServer"
TEMP_DIR="$(mktemp -d /tmp/torrserver-dmg.XXXXXX)"
STAGING_DIR="$TEMP_DIR/staging"
MOUNT_DIR="/Volumes/$VOLUME_NAME"
RW_DMG="$TEMP_DIR/TorrServer-rw.dmg"
DEVICE=""

for metadata_provider in TMDB OMDB Kinopoisk; do
  embedded_key="$(
    plutil -extract "TorrServeMetadataAPIKeys.$metadata_provider" raw \
      "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
  )"
  if [[ -z "$embedded_key" ]]; then
    echo "DMG packaging stopped: missing built-in $metadata_provider API key." >&2
    exit 1
  fi
done

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet 2>/dev/null || true
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR" "$STAGING_DIR/.background" "$STAGING_DIR/.fseventsd"
touch "$STAGING_DIR/.fseventsd/no_log"
rm -f "$DMG_PATH"

if [[ -e "$MOUNT_DIR" ]]; then
  echo "Volume is already mounted: $MOUNT_DIR" >&2
  exit 1
fi

ditto --norsrc "$APP_PATH" "$STAGING_DIR/TorrServer.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$APP_PATH/Contents/Resources/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"

xcrun swift "$PROJECT_DIR/scripts/render-dmg-background.swift" \
  "$STAGING_DIR/.background/background.png"

xattr -cr "$STAGING_DIR/TorrServer.app" 2>/dev/null || true
codesign --force --sign - --deep "$STAGING_DIR/TorrServer.app" >/dev/null
codesign --verify --deep --strict "$STAGING_DIR/TorrServer.app"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG" >/dev/null

DEVICE="$(
  hdiutil attach "$RW_DMG" \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$MOUNT_DIR" \
    | awk '/Apple_HFS/ { print $1; exit }'
)"

if SETFILE="$(xcrun -f SetFile 2>/dev/null)"; then
  "$SETFILE" -a C "$MOUNT_DIR" 2>/dev/null || true
fi

/usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
    delay 1
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set sidebar width of container window to 0
        set the bounds of container window to {120, 120, 840, 600}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 112
        set text size of theViewOptions to 13
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "TorrServer.app" of container window to {190, 255}
        set position of item "Applications" of container window to {530, 255}
        try
            set position of item ".background" of container window to {1100, 900}
        end try
        try
            set position of item ".fseventsd" of container window to {1200, 900}
        end try
        try
            set position of item ".VolumeIcon.icns" of container window to {1300, 900}
        end try
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$DEVICE" -quiet
DEVICE=""

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$DMG_PATH" >/dev/null

codesign --force --sign - "$DMG_PATH" >/dev/null
codesign --verify --verbose=1 "$DMG_PATH"

echo "$DMG_PATH"
