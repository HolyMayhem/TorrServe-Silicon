#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d /tmp/torrserve-telemetry-local.XXXXXX)"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -swift-version 5 -parse-as-library "$PROJECT_DIR"/Sources/Telemetry/*.swift \
  "$PROJECT_DIR/scripts/tests/telemetry-local.swift" -o "$CHECK_DIR/check"
TORRSERVE_TELEMETRY_DEBUG_URL="${TORRSERVE_TELEMETRY_DEBUG_URL:-http://127.0.0.1:8787/v1/heartbeat}" "$CHECK_DIR/check"
