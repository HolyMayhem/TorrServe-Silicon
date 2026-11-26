#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
cd "$PROJECT_DIR"
xcrun --sdk macosx clang -c -I Sources/TMDBHTTPS/include Sources/TMDBHTTPS/TMDBHTTPS.c -o "$CHECK_DIR/TMDBHTTPS.o"
swiftc -swift-version 5 -parse-as-library \
    -I Sources/TMDBHTTPS/include "$CHECK_DIR/TMDBHTTPS.o" -lcurl \
    Sources/Features/Catalog/Models/*.swift \
    Sources/Features/Catalog/Persistence/CatalogCache.swift \
    Sources/Features/Catalog/Services/*.swift \
    Sources/Features/Metadata/Models/MetadataModels.swift \
    Sources/Features/Metadata/Persistence/MetadataSettingsStore.swift \
    Sources/Features/Metadata/Services/{MetadataHTTPTransport,TMDBService,TMDBSecureDNS}.swift \
    Sources/Features/Library/Persistence/LibraryMetadataStore.swift \
    scripts/tests/catalog.swift -o "$CHECK_DIR/catalog-check"
"$CHECK_DIR/catalog-check"
