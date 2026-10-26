#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler is required (run this check on a Mac with Xcode)." >&2
  exit 1
fi
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
cp "$PROJECT_DIR/scripts/tests/notifications.swift" "$CHECK_DIR/main.swift"
swiftc "$PROJECT_DIR/Sources/Core/System/AppNotificationPreferences.swift" \
  "$PROJECT_DIR/Sources/Core/System/NotificationDeliveryState.swift" \
  "$CHECK_DIR/main.swift" -o "$CHECK_DIR/notification-check"
"$CHECK_DIR/notification-check"
