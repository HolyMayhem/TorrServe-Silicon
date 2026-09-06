#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="TorrServer.app"
APP_DIR="$PROJECT_DIR/build/app"
APP_PATH="$APP_DIR/$APP_NAME"
CONTENTS_DIR="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
GENERATED_DIR="$PROJECT_DIR/build/generated"
COMPILED_ICON_DIR="$GENERATED_DIR/AppIcon"
PARTIAL_INFO_PLIST="$GENERATED_DIR/AppIcon-Info.plist"
SOURCE_ICON="$PROJECT_DIR/Resources/AppIcon.icon"
XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ACTOOL="$XCODE_DEVELOPER_DIR/usr/bin/actool"
TORRSERVER_ASSET_NAME="TorrServer-darwin-arm64"
TORRSERVER_DOWNLOAD_URL="https://github.com/YouROK/TorrServer/releases/latest/download/$TORRSERVER_ASSET_NAME"
TORRSERVER_CACHE_DIR="$GENERATED_DIR/TorrServer"
TORRSERVER_CACHE_PATH="$TORRSERVER_CACHE_DIR/$TORRSERVER_ASSET_NAME"
SIGNING_DIR="$(mktemp -d /tmp/torrserver-app-sign.XXXXXX)"

cleanup() {
  rm -rf "$SIGNING_DIR"
}
trap cleanup EXIT

find "$PROJECT_DIR/Resources" -name ".DS_Store" -type f -delete

if [[ ! -d "$SOURCE_ICON" ]]; then
  echo "Missing Icon Composer document: $SOURCE_ICON" >&2
  exit 1
fi

if [[ ! -x "$ACTOOL" ]]; then
  echo "Xcode with Icon Composer support is required to build AppIcon.icon." >&2
  exit 1
fi

DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" swift build -c release --package-path "$PROJECT_DIR"
BIN_DIR="$(
  DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" \
    swift build -c release --package-path "$PROJECT_DIR" --show-bin-path
)"

rm -rf "$APP_PATH"
rm -rf "$COMPILED_ICON_DIR"
rm -f "$GENERATED_DIR/AppIconSystemDark.icns" "$PARTIAL_INFO_PLIST"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$COMPILED_ICON_DIR" "$TORRSERVER_CACHE_DIR"

if [[ -n "${TORRSERVER_EXECUTABLE:-}" ]]; then
  if [[ ! -f "$TORRSERVER_EXECUTABLE" ]]; then
    echo "TORRSERVER_EXECUTABLE does not point to a file: $TORRSERVER_EXECUTABLE" >&2
    exit 1
  fi
  cp "$TORRSERVER_EXECUTABLE" "$TORRSERVER_CACHE_PATH"
else
  TORRSERVER_TEMP_PATH="$TORRSERVER_CACHE_PATH.download"
  rm -f "$TORRSERVER_TEMP_PATH"
  if curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --retry 3 \
    --output "$TORRSERVER_TEMP_PATH" \
    "$TORRSERVER_DOWNLOAD_URL"; then
    mv "$TORRSERVER_TEMP_PATH" "$TORRSERVER_CACHE_PATH"
  elif [[ ! -f "$TORRSERVER_CACHE_PATH" ]]; then
    echo "Could not download the bundled TorrServer executable." >&2
    exit 1
  else
    echo "Warning: using the cached TorrServer executable." >&2
  fi
fi

if ! file "$TORRSERVER_CACHE_PATH" | grep -Eq 'Mach-O.*arm64'; then
  echo "The bundled TorrServer executable is not a macOS arm64 binary." >&2
  exit 1
fi
chmod 755 "$TORRSERVER_CACHE_PATH"

DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" "$ACTOOL" \
  --compile "$COMPILED_ICON_DIR" \
  --platform macosx \
  --minimum-deployment-target 15.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$PARTIAL_INFO_PLIST" \
  --warnings \
  --notices \
  --errors \
  "$SOURCE_ICON" >/dev/null

test -f "$COMPILED_ICON_DIR/AppIcon.icns"
test -f "$COMPILED_ICON_DIR/Assets.car"
test "$(plutil -extract CFBundleIconName raw "$PARTIAL_INFO_PLIST")" = "AppIcon"

cp "$BIN_DIR/TorrServerManager" "$MACOS_DIR/TorrServerManager"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/PkgInfo" "$CONTENTS_DIR/PkgInfo"
cp "$COMPILED_ICON_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$COMPILED_ICON_DIR/Assets.car" "$RESOURCES_DIR/Assets.car"
cp "$TORRSERVER_CACHE_PATH" "$RESOURCES_DIR/$TORRSERVER_ASSET_NAME"
chmod 755 "$RESOURCES_DIR/$TORRSERVER_ASSET_NAME"

DEFAULT_METADATA_KEYS_FILE="$PROJECT_DIR/Config/MetadataKeys.plist"
METADATA_KEYS_SOURCE="${METADATA_KEYS_FILE:-$DEFAULT_METADATA_KEYS_FILE}"
REQUIRE_METADATA_KEYS="${REQUIRE_METADATA_KEYS:-0}"
TMDB_METADATA_KEY=""
OMDB_METADATA_KEY=""
KINOPOISK_METADATA_KEY=""

read_metadata_key() {
  local primary_name="$1"
  local legacy_name="$2"
  local value

  value="$(plutil -extract "$primary_name" raw "$METADATA_KEYS_SOURCE" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    value="$(plutil -extract "$legacy_name" raw "$METADATA_KEYS_SOURCE" 2>/dev/null || true)"
  fi
  printf '%s' "$value"
}

if [[ -f "$METADATA_KEYS_SOURCE" ]]; then
  TMDB_METADATA_KEY="$(read_metadata_key TMDB tmdbAPIKey)"
  OMDB_METADATA_KEY="$(read_metadata_key OMDB omdbAPIKey)"
  KINOPOISK_METADATA_KEY="$(read_metadata_key Kinopoisk kinopoiskAPIKey)"
fi

MISSING_METADATA_KEYS=""
if [[ -z "$TMDB_METADATA_KEY" ]]; then MISSING_METADATA_KEYS="$MISSING_METADATA_KEYS TMDB"; fi
if [[ -z "$OMDB_METADATA_KEY" ]]; then MISSING_METADATA_KEYS="$MISSING_METADATA_KEYS OMDB"; fi
if [[ -z "$KINOPOISK_METADATA_KEY" ]]; then MISSING_METADATA_KEYS="$MISSING_METADATA_KEYS Kinopoisk"; fi

if [[ "$REQUIRE_METADATA_KEYS" == "1" && -n "$MISSING_METADATA_KEYS" ]]; then
  echo "Missing required built-in metadata keys:$MISSING_METADATA_KEYS" >&2
  echo "Create $DEFAULT_METADATA_KEYS_FILE from Config/MetadataKeys.example.plist or set METADATA_KEYS_FILE." >&2
  exit 1
fi

if [[ -n "$TMDB_METADATA_KEY" || -n "$OMDB_METADATA_KEY" || -n "$KINOPOISK_METADATA_KEY" ]]; then
  /usr/libexec/PlistBuddy -c "Delete :TorrServeMetadataAPIKeys" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :TorrServeMetadataAPIKeys dict" "$CONTENTS_DIR/Info.plist"
  if [[ -n "$TMDB_METADATA_KEY" ]]; then
    /usr/libexec/PlistBuddy -c "Add :TorrServeMetadataAPIKeys:TMDB string $TMDB_METADATA_KEY" "$CONTENTS_DIR/Info.plist"
  fi
  if [[ -n "$OMDB_METADATA_KEY" ]]; then
    /usr/libexec/PlistBuddy -c "Add :TorrServeMetadataAPIKeys:OMDB string $OMDB_METADATA_KEY" "$CONTENTS_DIR/Info.plist"
  fi
  if [[ -n "$KINOPOISK_METADATA_KEY" ]]; then
    /usr/libexec/PlistBuddy -c "Add :TorrServeMetadataAPIKeys:Kinopoisk string $KINOPOISK_METADATA_KEY" "$CONTENTS_DIR/Info.plist"
  fi
  echo "Embedded built-in metadata keys from $METADATA_KEYS_SOURCE" >&2
else
  echo "Warning: built-in metadata keys are unavailable; custom-key mode will still work." >&2
fi

chflags -R nohidden "$APP_PATH" 2>/dev/null || true
SIGNED_APP_PATH="$SIGNING_DIR/$APP_NAME"
ditto --norsrc "$APP_PATH" "$SIGNED_APP_PATH"
xattr -cr "$SIGNED_APP_PATH" 2>/dev/null || true
codesign --force --sign - "$SIGNED_APP_PATH/Contents/Resources/$TORRSERVER_ASSET_NAME"
codesign --force --sign - --deep "$SIGNED_APP_PATH"
codesign --verify --deep --strict "$SIGNED_APP_PATH"

rm -rf "$APP_PATH"
ditto --norsrc "$SIGNED_APP_PATH" "$APP_PATH"
xattr -cr "$APP_PATH" 2>/dev/null || true

# Documents may be managed by File Provider, which can immediately attach
# FinderInfo after the final copy. Verify the same resource-clean representation
# that the DMG packager receives instead of racing those external attributes.
VERIFICATION_APP_PATH="$SIGNING_DIR/Verified-$APP_NAME"
ditto --norsrc "$APP_PATH" "$VERIFICATION_APP_PATH"
xattr -cr "$VERIFICATION_APP_PATH" 2>/dev/null || true
codesign --verify --deep --strict "$VERIFICATION_APP_PATH"

echo "$APP_PATH"
