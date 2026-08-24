#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command openssl
require_command python3
require_command curl
require_command jq

TMPDIR=$(mktemp -d)
SERVER_PID=""
trap '[[ -n $SERVER_PID ]] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$TMPDIR"' EXIT

# --- A tiny signed registry on localhost -----------------------------------

docroot="$TMPDIR/registry"
mkdir -p "$docroot/index/test" "$docroot/dl/test/widget"

openssl genpkey -algorithm ed25519 -out "$TMPDIR/signing.pem" 2>/dev/null
openssl pkey -in "$TMPDIR/signing.pem" -pubout -outform DER | tail -c 32 | base64 -w0 \
  >"$docroot/signing-key.pub"

sign() {
  openssl pkeyutl -sign -inkey "$TMPDIR/signing.pem" -rawin -in "$1" | base64 -w0 >"$1.sig"
}

now_gen=1000
tomorrow=$(date -u -d "+1 day" +%FT%TZ)
yesterday=$(date -u -d "-1 day" +%FT%TZ)

tarball="$docroot/dl/test/widget/widget-1.1.0.tar.gz"
workdir="$TMPDIR/plugin"
mkdir -p "$workdir"
cat >"$workdir/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "test.widget",
  "name": "Widget",
  "version": "1.1.0",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" }
}
JSON
printf 'import QtQuick\nItem {}\n' >"$workdir/Widget.qml"
tar -czf "$tarball" -C "$workdir" manifest.json Widget.qml
sha=$(sha256sum "$tarball" | cut -d' ' -f1)

write_data_plane() {
  local gen="$1" expires="$2"
  cat >"$docroot/revocations.json" <<JSON
{"schemaVersion":1,"revocations":[],"generation":$gen,"generated_at":"2026-01-01T00:00:00Z","expires_at":"$expires"}
JSON
  sign "$docroot/revocations.json"

  {
    echo "{\"meta\":true,\"generation\":$gen,\"expires_at\":\"$expires\"}"
    echo "{\"id\":\"test.widget\",\"vers\":\"1.0.0\",\"sha256\":\"aaaa\",\"yanked\":false}"
    echo "{\"id\":\"test.widget\",\"vers\":\"1.1.0\",\"sha256\":\"$sha\",\"yanked\":false}"
    echo "{\"id\":\"test.widget\",\"vers\":\"1.2.0\",\"sha256\":\"bbbb\",\"yanked\":true}"
  } >"$docroot/index/test/widget.json"
  sign "$docroot/index/test/widget.json"

  cat >"$docroot/config.json" <<JSON
{"dl":"$BASE/dl/{publisher}/{name}/{name}-{version}.tar.gz","generation":$gen,"expires_at":"$expires"}
JSON
  sign "$docroot/config.json"
}

port=$(( 20000 + RANDOM % 20000 ))
BASE="http://127.0.0.1:$port"
( cd "$docroot" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 ) &
SERVER_PID=$!
for _ in $(seq 40); do
  curl -sf "$BASE/signing-key.pub" >/dev/null 2>&1 && break
  sleep 0.05
done

write_data_plane "$now_gen" "$tomorrow"

reg() {
  OMARCHY_PLUGIN_REGISTRY_URL="$BASE" \
    OMARCHY_PLUGIN_REGISTRY_STATE="$TMPDIR/state" \
    "$ROOT/bin/omarchy-plugin-registry" "$@"
}

reg pubkey >/dev/null 2>&1 || fail "could not pin the test registry key"

# --- Verified fetch --------------------------------------------------------

output=$(reg revocations 2>&1) ||
  fail "verified revocations fetch fails on a well-signed data plane" "$output"
jq -e '.revocations == []' <<<"$output" >/dev/null ||
  fail "revocations output is not the kill list" "$output"
pass "signed kill list verifies and parses"

[[ -f $TMPDIR/state/127.0.0.1_$port/signing-key.pem ]] ||
  fail "signing key was not pinned on first use"
pass "signing key is pinned on first use"

# --- Tampering is fatal ----------------------------------------------------

sed -i 's/"revocations":\[\]/"revocations":[{"plugin":"x","reason":"y"}]/' "$docroot/revocations.json"
output=$(reg revocations 2>&1) &&
  fail "tampered kill list was accepted" "$output"
grep -q "SIGNATURE VERIFICATION FAILED" <<<"$output" ||
  fail "tampered kill list did not fail on signature" "$output"
pass "tampered kill list is rejected"
write_data_plane "$now_gen" "$tomorrow"

# --- Freshness is fatal ----------------------------------------------------

write_data_plane "$(( now_gen + 1 ))" "$yesterday"
output=$(reg revocations 2>&1) &&
  fail "expired kill list was accepted" "$output"
grep -q "EXPIRED" <<<"$output" ||
  fail "expired kill list did not fail on freshness" "$output"
pass "expired kill list fails closed"

# --- Rollback is fatal -----------------------------------------------------

write_data_plane "$(( now_gen + 5 ))" "$tomorrow"
reg revocations >/dev/null 2>&1 || fail "could not accept the newer generation"
write_data_plane "$(( now_gen + 2 ))" "$tomorrow"
output=$(reg revocations 2>&1) &&
  fail "older generation displaced a newer one" "$output"
grep -q "OLDER than last accepted" <<<"$output" ||
  fail "rollback did not fail on generation" "$output"
pass "generation rollback is rejected"
write_data_plane "$(( now_gen + 6 ))" "$tomorrow"

# --- Resolve ---------------------------------------------------------------

output=$(reg resolve test/widget 2>&1) ||
  fail "resolve failed on a valid index" "$output"
[[ $(jq -r '.vers' <<<"$output") == 1.1.0 ]] ||
  fail "resolve did not pick the highest non-yanked version" "$output"
pass "resolve picks the highest non-yanked version"

# --- Revoked versions are refused ------------------------------------------

gen=$(( now_gen + 7 ))
write_data_plane "$gen" "$tomorrow"
cat >"$docroot/revocations.json" <<JSON
{"schemaVersion":1,"revocations":[{"plugin":"test.widget","version":"1.1.0","reason":"drill"}],"generation":$gen,"generated_at":"2026-01-01T00:00:00Z","expires_at":"$tomorrow"}
JSON
sign "$docroot/revocations.json"
output=$(reg resolve test/widget 2>&1) &&
  fail "resolve returned a revoked version" "$output"
grep -q "REVOKED" <<<"$output" ||
  fail "revoked resolve did not name the kill list" "$output"
pass "resolve refuses a revoked version"
write_data_plane "$(( now_gen + 8 ))" "$tomorrow"

# --- Download verifies the checksum ----------------------------------------

output=$(reg download test/widget 1.1.0 "$TMPDIR/out.tar.gz" 2>&1) ||
  fail "download failed on a valid tarball" "$output"
[[ $(sha256sum "$TMPDIR/out.tar.gz" | cut -d' ' -f1) == "$sha" ]] ||
  fail "downloaded tarball does not match the index checksum"
pass "download verifies the index sha256"

printf 'EVIL' >>"$tarball"
output=$(reg download test/widget 1.1.0 "$TMPDIR/out2.tar.gz" 2>&1) &&
  fail "corrupted tarball was accepted" "$output"
grep -q "CHECKSUM MISMATCH" <<<"$output" ||
  fail "corrupted tarball did not fail on checksum" "$output"
[[ ! -e $TMPDIR/out2.tar.gz ]] ||
  fail "corrupted tarball was left on disk"
pass "checksum mismatch refuses and cleans up"
