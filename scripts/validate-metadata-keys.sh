#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_KEYS_SOURCE="${1:-${METADATA_KEYS_FILE:-$PROJECT_DIR/Config/MetadataKeys.plist}}"
TEMP_DIR="$(mktemp -d /tmp/torrserver-metadata-keys.XXXXXX)"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

read_metadata_key() {
  local primary_name="$1"
  local legacy_name="$2"
  local value

  value="$(plutil -extract "$primary_name" raw "$METADATA_KEYS_SOURCE" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    value="$(plutil -extract "$legacy_name" raw "$METADATA_KEYS_SOURCE" 2>/dev/null || true)"
  fi
  printf '%s' "$value"
}

if [[ ! -f "$METADATA_KEYS_SOURCE" ]]; then
  echo "Metadata keys file not found: $METADATA_KEYS_SOURCE" >&2
  exit 1
fi

TMDB_METADATA_KEY="$(read_metadata_key TMDB tmdbAPIKey)"
OMDB_METADATA_KEY="$(read_metadata_key OMDB omdbAPIKey)"
KINOPOISK_METADATA_KEY="$(read_metadata_key Kinopoisk kinopoiskAPIKey)"

for required_key in TMDB_METADATA_KEY OMDB_METADATA_KEY KINOPOISK_METADATA_KEY; do
  if [[ -z "${!required_key}" ]]; then
    echo "Metadata key is missing: ${required_key%_METADATA_KEY}" >&2
    exit 1
  fi
done

TMDB_STATUS="$(
  curl \
    --silent \
    --show-error \
    --max-time 15 \
    --doh-url "https://dns.google/dns-query" \
    --output "$TEMP_DIR/tmdb.json" \
    --write-out '%{http_code}' \
    --get \
    --data-urlencode "api_key=$TMDB_METADATA_KEY" \
    "https://api.themoviedb.org/3/authentication" || true
)"
if [[ "$TMDB_STATUS" != "200" ]]; then
  echo "TMDB built-in key validation failed (HTTP ${TMDB_STATUS:-000})." >&2
  exit 1
fi
echo "TMDB built-in key: valid"

OMDB_STATUS="$(
  curl \
    --silent \
    --show-error \
    --max-time 15 \
    --output "$TEMP_DIR/omdb.json" \
    --write-out '%{http_code}' \
    --get \
    --data-urlencode "apikey=$OMDB_METADATA_KEY" \
    --data-urlencode "i=tt0133093" \
    --data-urlencode "r=json" \
    "https://www.omdbapi.com/" || true
)"
OMDB_ACCEPTED="$(plutil -extract Response raw "$TEMP_DIR/omdb.json" 2>/dev/null || true)"
if [[ "$OMDB_STATUS" != "200" || "$OMDB_ACCEPTED" != "True" ]]; then
  echo "OMDb built-in key validation failed (HTTP ${OMDB_STATUS:-000})." >&2
  exit 1
fi
echo "OMDb built-in key: valid"

KINOPOISK_STATUS="$(
  curl \
    --silent \
    --show-error \
    --max-time 15 \
    --output "$TEMP_DIR/kinopoisk.json" \
    --write-out '%{http_code}' \
    --header "Accept: application/json" \
    --header "X-API-KEY: $KINOPOISK_METADATA_KEY" \
    "https://kinopoiskapiunofficial.tech/api/v2.2/films/301" || true
)"
if [[ "$KINOPOISK_STATUS" != "200" ]]; then
  echo "Kinopoisk built-in key validation failed (HTTP ${KINOPOISK_STATUS:-000})." >&2
  exit 1
fi
echo "Kinopoisk built-in key: valid"
