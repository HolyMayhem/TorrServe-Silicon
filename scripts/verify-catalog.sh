#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
cd "$PROJECT_DIR"
swiftc -swift-version 5 -parse-as-library \
    Sources/Features/Catalog/Models/*.swift \
    Sources/Features/Catalog/Persistence/CatalogCache.swift \
    Sources/Features/Catalog/Services/*.swift \
    Sources/Features/Metadata/Models/MetadataModels.swift \
    Sources/Features/Metadata/Persistence/MetadataSettingsStore.swift \
    Sources/Features/Metadata/Services/{MetadataHTTPTransport,TMDBService}.swift \
    Sources/Features/Library/Persistence/LibraryMetadataStore.swift \
    scripts/tests/catalog.swift -o "$CHECK_DIR/catalog-check"
"$CHECK_DIR/catalog-check"
