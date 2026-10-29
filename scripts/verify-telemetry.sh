#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# A scratch directory outside Documents also avoids File Provider FinderInfo signing errors.
SCRATCH_DIR="$(mktemp -d /tmp/torrserve-telemetry-tests.XXXXXX)"
trap 'rm -rf "$SCRATCH_DIR"' EXIT
TORRSERVE_TELEMETRY_TESTS_ONLY=1 swift test --package-path "$PROJECT_DIR" \
  --scratch-path "$SCRATCH_DIR" --filter TelemetryTests
