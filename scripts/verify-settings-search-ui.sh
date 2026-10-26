#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler and macOS SDK are required." >&2
  exit 1
fi
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -swift-version 5 -parse-as-library \
  "$PROJECT_DIR/Sources/Features/Settings/Search/SettingsSearchIndex.swift" \
  "$PROJECT_DIR/Sources/Features/Settings/Search/SettingsSearchViews.swift" \
  "$PROJECT_DIR/scripts/tests/settings-search-ui.swift" -o "$CHECK_DIR/settings-search-ui-check"
"$CHECK_DIR/settings-search-ui-check"
