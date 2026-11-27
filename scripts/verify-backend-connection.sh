#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
cd "$PROJECT_DIR"
swiftc -swift-version 5 -parse-as-library \
    Sources/App/Localization/AppLocalization.swift \
    Sources/Core/Configuration/AppConstants.swift \
    Sources/Core/Errors/{AppError,TorrentAddError}.swift \
    Sources/Core/TorrServer/{TorrServerLocalLog,TorrServerModels,TorrServerNativeAPI,TorrServerVersion,TorrentAddDiagnostics,TorrentFileValidator}.swift \
    Sources/Features/Server/Services/{TorrServerProcessController,TorrServerReleaseChecker,TorrServerDownloader}.swift \
    scripts/tests/backend-connection.swift -o "$CHECK_DIR/backend-connection"
CFFIXED_USER_HOME="$CHECK_DIR" "$CHECK_DIR/backend-connection" "$CHECK_DIR" "$@"
