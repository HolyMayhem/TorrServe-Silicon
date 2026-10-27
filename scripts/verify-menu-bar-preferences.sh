#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -swift-version 5 -parse-as-library \
  "$PROJECT_DIR/Sources/App/Localization/AppLocalization.swift" \
  "$PROJECT_DIR/Sources/Features/MenuBar/Models/MenuBarPreferences.swift" \
  "$PROJECT_DIR/Sources/Features/MenuBar/Models/MenuBarCacheSnapshot.swift" \
  "$PROJECT_DIR/scripts/tests/menu-bar-preferences.swift" -o "$CHECK_DIR/menu-bar-preferences-check"
"$CHECK_DIR/menu-bar-preferences-check"
