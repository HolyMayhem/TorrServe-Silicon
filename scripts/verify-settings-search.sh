#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler is required (run this check on a Mac with Xcode)." >&2
  exit 1
fi
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
cp "$PROJECT_DIR/scripts/tests/settings-search.swift" "$CHECK_DIR/main.swift"
swiftc "$PROJECT_DIR/Sources/Features/Settings/Search/SettingsSearchIndex.swift" \
  "$CHECK_DIR/main.swift" -o "$CHECK_DIR/settings-search-check"
"$CHECK_DIR/settings-search-check"
