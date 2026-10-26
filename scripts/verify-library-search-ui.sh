#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -swift-version 5 -parse-as-library \
  "$PROJECT_DIR/Sources/Features/Library/Views/LibrarySearchField.swift" \
  "$PROJECT_DIR/scripts/tests/library-search-ui.swift" -o "$CHECK_DIR/library-search-ui-check"
"$CHECK_DIR/library-search-ui-check"
