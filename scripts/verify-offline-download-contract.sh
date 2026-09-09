#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <stream-url> <expected-file-size>" >&2
  echo "The stream URL must already contain link, index, and play query parameters." >&2
  exit 64
fi

STREAM_URL="$1"
EXPECTED_SIZE="$2"

if [[ ! "$EXPECTED_SIZE" =~ ^[1-9][0-9]*$ ]] || (( EXPECTED_SIZE < 2 )); then
  echo "Expected file size must be an integer greater than 1." >&2
  exit 64
fi

TEMP_DIR="$(mktemp -d /tmp/torrserve-offline-contract.XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

FULL_HEADERS="$TEMP_DIR/full.headers"
RANGE_HEADERS="$TEMP_DIR/range.headers"
MISMATCH_HEADERS="$TEMP_DIR/mismatch.headers"
INVALID_HEADERS="$TEMP_DIR/invalid.headers"

header_value() {
  local header_name="$1"
  local header_file="$2"
  awk -F ': *' -v name="$header_name" '
    tolower($1) == tolower(name) {
      sub(/\r$/, "", $2)
      value = $2
    }
    END { print value }
  ' "$header_file"
}

status_code() {
  awk '/^HTTP\// { code = $2 } END { print code }' "$1"
}

assert_equal() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$label: expected '$expected', got '$actual'." >&2
    exit 1
  fi
}

curl --fail-with-body --silent --show-error --max-time 45 \
  --head --dump-header "$FULL_HEADERS" --output /dev/null \
  "$STREAM_URL"

assert_equal "Initial status" "200" "$(status_code "$FULL_HEADERS")"
assert_equal \
  "Initial Content-Length" \
  "$EXPECTED_SIZE" \
  "$(header_value Content-Length "$FULL_HEADERS")"

ACCEPT_RANGES="$(header_value Accept-Ranges "$FULL_HEADERS")"
ACCEPT_RANGES_LOWER="$(printf '%s' "$ACCEPT_RANGES" | tr '[:upper:]' '[:lower:]')"
if [[ "$ACCEPT_RANGES_LOWER" != *"bytes"* ]]; then
  echo "TorrServer did not advertise byte ranges." >&2
  exit 1
fi

ENTITY_TAG="$(header_value ETag "$FULL_HEADERS")"
ENTITY_TAG_PREFIX="$(printf '%.2s' "$ENTITY_TAG" | tr '[:upper:]' '[:lower:]')"
if [[ -z "$ENTITY_TAG" || "$ENTITY_TAG_PREFIX" == "w/" ]]; then
  echo "TorrServer did not return a strong ETag." >&2
  exit 1
fi

if (( EXPECTED_SIZE > 1048576 )); then
  RESUME_OFFSET=1048576
else
  RESUME_OFFSET=1
fi

curl --fail-with-body --silent --show-error --max-time 45 \
  --head --dump-header "$RANGE_HEADERS" --output /dev/null \
  --header "Range: bytes=$RESUME_OFFSET-" \
  --header "If-Range: $ENTITY_TAG" \
  "$STREAM_URL"

assert_equal "Resume status" "206" "$(status_code "$RANGE_HEADERS")"
assert_equal \
  "Resume Content-Range" \
  "bytes $RESUME_OFFSET-$((EXPECTED_SIZE - 1))/$EXPECTED_SIZE" \
  "$(header_value Content-Range "$RANGE_HEADERS")"
assert_equal \
  "Resume Content-Length" \
  "$((EXPECTED_SIZE - RESUME_OFFSET))" \
  "$(header_value Content-Length "$RANGE_HEADERS")"
assert_equal "Resume ETag" "$ENTITY_TAG" "$(header_value ETag "$RANGE_HEADERS")"

curl --silent --show-error --max-time 45 \
  --head --dump-header "$MISMATCH_HEADERS" --output /dev/null \
  --header "Range: bytes=$RESUME_OFFSET-" \
  --header 'If-Range: "torrserve-contract-mismatch"' \
  "$STREAM_URL"

assert_equal \
  "Mismatched If-Range status" \
  "200" \
  "$(status_code "$MISMATCH_HEADERS")"

curl --silent --show-error --max-time 45 \
  --head --dump-header "$INVALID_HEADERS" --output /dev/null \
  --header "Range: bytes=$EXPECTED_SIZE-" \
  "$STREAM_URL"

assert_equal \
  "Unsatisfiable range status" \
  "416" \
  "$(status_code "$INVALID_HEADERS")"

PROBE_END=15
if (( EXPECTED_SIZE <= PROBE_END )); then
  PROBE_END=$((EXPECTED_SIZE - 1))
fi
PROBE_RESULT="$(
  curl --silent --show-error --max-time 60 \
    --output /dev/null \
    --write-out '%{http_code} %{size_download}' \
    --header "Range: bytes=0-$PROBE_END" \
    "$STREAM_URL"
)"

assert_equal "Byte probe" "206 $((PROBE_END + 1))" "$PROBE_RESULT"

echo "Offline-download HTTP contract verified."
echo "ETag: $ENTITY_TAG"
echo "Content-Length: $EXPECTED_SIZE"
echo "Resume offset: $RESUME_OFFSET"
