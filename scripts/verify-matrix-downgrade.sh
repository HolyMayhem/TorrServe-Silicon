#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler and macOS SDK are required (run on a Mac with Xcode)." >&2
  exit 1
fi
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -swift-version 5 -parse-as-library \
  "$PROJECT_DIR/Sources/Core/Errors/AppError.swift" \
  "$PROJECT_DIR/Sources/Core/Configuration/AppConstants.swift" \
  "$PROJECT_DIR/Sources/Features/Server/Services/TorrServerReleaseChecker.swift" \
  "$PROJECT_DIR/Sources/Features/Server/Services/TorrServerDownloader.swift" \
  "$PROJECT_DIR/Sources/Features/Server/Services/TorrServerUpdateInstaller.swift" \
  "$PROJECT_DIR/scripts/tests/matrix-downgrade.swift" -o "$CHECK_DIR/matrix-downgrade-check"
"$CHECK_DIR/matrix-downgrade-check"
