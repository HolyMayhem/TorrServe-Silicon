#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$PROJECT_DIR/scripts/validate-whats-new.py" "$PROJECT_DIR/Resources/WhatsNew.json" "$PROJECT_DIR/Resources/Info.plist"
if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler is required." >&2
  exit 1
fi
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
cp "$PROJECT_DIR/scripts/tests/whats-new.swift" "$CHECK_DIR/main.swift"
swiftc -swift-version 5 "$PROJECT_DIR/Sources/Features/Updates/WhatsNew/WhatsNewManifest.swift" \
  "$CHECK_DIR/main.swift" -o "$CHECK_DIR/whats-new-check"
"$CHECK_DIR/whats-new-check" "$PROJECT_DIR/Resources/WhatsNew.json"
