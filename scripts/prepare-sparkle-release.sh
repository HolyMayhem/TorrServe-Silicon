#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-com.holymayhem.torrserve-silicon-updates}"
SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:-$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin}"
GENERATE_KEYS="$SPARKLE_TOOLS_DIR/generate_keys"
GENERATE_APPCAST="$SPARKLE_TOOLS_DIR/generate_appcast"

for tool in "$GENERATE_KEYS" "$GENERATE_APPCAST"; do
  if [[ ! -x "$tool" ]]; then
    echo "Missing Sparkle tool: $tool" >&2
    echo "Run: swift package resolve" >&2
    exit 1
  fi
done

VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
BUILD_NUMBER="$(plutil -extract CFBundleVersion raw "$INFO_PLIST")"
RELEASE_TAG="${RELEASE_TAG:-v$VERSION}"
CONFIGURED_PUBLIC_KEY="$(plutil -extract SUPublicEDKey raw "$INFO_PLIST")"
KEYCHAIN_PUBLIC_KEY="$(
  "$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p
)"

if [[ "$CONFIGURED_PUBLIC_KEY" != "$KEYCHAIN_PUBLIC_KEY" ]]; then
  echo "The Sparkle key in Info.plist does not match account $SPARKLE_ACCOUNT." >&2
  exit 1
fi

DMG_PATH="$(
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    "$PROJECT_DIR/scripts/package-dmg.sh" \
    | tail -n 1
)"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG packaging did not produce a file: $DMG_PATH" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d /tmp/torrserve-sparkle-release.XXXXXX)"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

DMG_NAME="$(basename "$DMG_PATH")"
cp "$DMG_PATH" "$STAGING_DIR/$DMG_NAME"

if [[ -n "${RELEASE_NOTES_FILE:-}" ]]; then
  if [[ ! -f "$RELEASE_NOTES_FILE" ]]; then
    echo "Release notes file not found: $RELEASE_NOTES_FILE" >&2
    exit 1
  fi
  cp "$RELEASE_NOTES_FILE" "$STAGING_DIR/${DMG_NAME%.dmg}.md"
fi

"$GENERATE_APPCAST" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix \
    "https://github.com/HolyMayhem/TorrServe-Silicon/releases/download/$RELEASE_TAG/" \
  --link "https://github.com/HolyMayhem/TorrServe-Silicon/releases" \
  --embed-release-notes \
  --maximum-deltas 0 \
  -o "$PROJECT_DIR/appcast.xml" \
  "$STAGING_DIR"

xmllint --noout "$PROJECT_DIR/appcast.xml"

if ! grep -q 'sparkle:edSignature=' "$PROJECT_DIR/appcast.xml"; then
  echo "Generated appcast does not contain an EdDSA signature." >&2
  exit 1
fi

if ! grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" \
  "$PROJECT_DIR/appcast.xml"; then
  echo "Generated appcast does not contain build $BUILD_NUMBER." >&2
  exit 1
fi

echo "Prepared TorrServe Silicon $VERSION ($BUILD_NUMBER)"
echo "Release tag: $RELEASE_TAG"
echo "DMG: $DMG_PATH"
echo "SHA-256: $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo "Appcast: $PROJECT_DIR/appcast.xml"
