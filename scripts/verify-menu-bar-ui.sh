#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -swift-version 5 -parse-as-library \
  "$PROJECT_DIR/Sources/App/Localization/AppLocalization.swift" \
  "$PROJECT_DIR/Sources/Core/Presentation/MainStatusKind.swift" \
  "$PROJECT_DIR/Sources/Features/MenuBar/Models/MenuBarPreferences.swift" \
  "$PROJECT_DIR/Sources/Features/MenuBar/Models/MenuBarCacheSnapshot.swift" \
  "$PROJECT_DIR/Sources/Features/Settings/Views/MenuBarSectionOrderView.swift" \
  "$PROJECT_DIR/Sources/Features/MenuBar/Views/MenuBarPopoverView.swift" \
  "$PROJECT_DIR/Sources/Features/MenuBar/Views/MenuBarPopoverController.swift" \
  "$PROJECT_DIR/scripts/tests/menu-bar-ui.swift" -o "$CHECK_DIR/menu-bar-ui-check"
"$CHECK_DIR/menu-bar-ui-check"
