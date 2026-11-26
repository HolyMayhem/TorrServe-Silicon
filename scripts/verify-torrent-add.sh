#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
SERVER_PID=
cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$CHECK_DIR"
}
trap cleanup EXIT
cd "$PROJECT_DIR"

sources=(
    Sources/App/Localization/AppLocalization.swift
    Sources/Core/Errors/{AppError,TorrentAddError}.swift
    Sources/Core/TorrServer/{TorrServerModels,TorrServerNativeAPI,TorrentAddDiagnostics,TorrentFileValidator}.swift
    Sources/Features/Search/Models/{JackettModels,TorrentSearchModels}.swift
    Sources/Features/Search/Parsing/{JackettTorznabParser,TorrentSearchResponseParser}.swift
    Sources/Features/Search/Services/{JackettClient,JackettRequestScope}.swift
)
if [[ "$(uname -s)" == Darwin ]]; then
    sources+=(
        Sources/Core/Formatting/TransferFormatting.swift
        Sources/Core/Presentation/AppAlert.swift
        Sources/Features/Catalog/Models/{CatalogModels,CatalogTorrentContext,CatalogGenreDefaults}.swift
        Sources/Features/Metadata/Models/MetadataModels.swift
        Sources/Features/Search/Models/SearchPresentationModels.swift
        Sources/Features/Search/Persistence/JackettCredentialStore.swift
        Sources/Features/Search/Services/TorrentSearchClient.swift
        Sources/Features/Search/ViewModels/SearchViewModel.swift
        Sources/Features/Search/Views/SearchPresentationSupport.swift
    )
fi
swiftc -swift-version 5 -parse-as-library "${sources[@]}" \
    scripts/tests/torrent-add.swift -o "$CHECK_DIR/torrent-add-check"

python3 scripts/tests/torrent-add-http.py "$CHECK_DIR/ports" &
SERVER_PID=$!
for ((attempt = 0; attempt < 100; attempt++)); do
    if [[ -s "$CHECK_DIR/ports" ]]; then break; fi
    kill -0 "$SERVER_PID"
    sleep 0.05
done
"$CHECK_DIR/torrent-add-check" "$CHECK_DIR/ports"
