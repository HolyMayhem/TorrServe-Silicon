#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${1:-http://127.0.0.1:8787}"
case "$BASE_URL" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo 'This scenario writes test events and only permits loopback URLs.' >&2; exit 1 ;;
esac
WORK_DIR="$(mktemp -d /tmp/torrserve-telemetry-smoke.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
curl --fail --silent --show-error "$BASE_URL/admin/api/stats" > "$WORK_DIR/before.json"
python3 - "$WORK_DIR/body.json" <<'PY'
import json, sys, uuid
json.dump(dict(schemaVersion=1, installationID=str(uuid.uuid4()), appVersion='2.8.0', macOSVersion='15.7.0', cpuArchitecture='arm64', cpuModel='Apple M4 Pro'),open(sys.argv[1],'w'))
PY
for iteration in 1 2; do
  CODE="$(curl --silent --show-error --output "$WORK_DIR/result" --write-out '%{http_code}' \
    -H 'Content-Type: application/json' --data-binary "@$WORK_DIR/body.json" "$BASE_URL/v1/heartbeat")"
  test "$CODE" = 204 || { echo "Expected 204, got $CODE" >&2; exit 1; }
done
curl --fail --silent --show-error "$BASE_URL/admin/api/stats" > "$WORK_DIR/after.json"
python3 - "$WORK_DIR/before.json" "$WORK_DIR/after.json" <<'PY'
import json, sys
before, after = [json.load(open(p)) for p in sys.argv[1:]]
for metric in ['installations','dau','wau','mau']:
    assert after['metrics'][metric] == before['metrics'][metric] + 1, metric
assert after['activity'][-1]['active'] == before['activity'][-1]['active'] + 1
assert after['activity'][-1]['new_installations'] == before['activity'][-1]['new_installations'] + 1
print('PASS: replayed heartbeat adds exactly one installation and one active ID.')
PY
CODE="$(curl --silent --show-error --output "$WORK_DIR/invalid" --write-out '%{http_code}' \
  -H 'Content-Type: application/json' --data '{"torrentName":"must be rejected"}' "$BASE_URL/v1/heartbeat")"
test "$CODE" = 400
printf '%s\n' 'PASS: unexpected personal-data field rejected with HTTP 400.'
