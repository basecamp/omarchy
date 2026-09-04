#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/home" "$TMPDIR/bin"
calls="$TMPDIR/calls"

cat >"$TMPDIR/bin/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
printf 'ok\n'
SH
chmod +x "$TMPDIR/bin/omarchy-shell"

run_enable() {
  HOME="$TMPDIR/home" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_TEST_CALLS="$calls" \
    PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
    omarchy-plugin-enable "$@"
}

run_enable omarchy.active-window --section right >/dev/null
grep -Fqx 'shell enablePlugin omarchy.active-window {"section":"right"}' "$calls" ||
  fail "plugin enable did not combine activation and placement"
pass "plugin enable combines activation and placement in one shell mutation"

run_enable omarchy.clock --before omarchy.weather >/dev/null
grep -Fqx 'shell enablePlugin omarchy.clock {"before":"omarchy.weather"}' "$calls" ||
  fail "plugin enable did not preserve relative placement"
pass "plugin enable forwards relative placement"

run_enable omarchy.dropbox >/dev/null
grep -Fqx 'shell enablePlugin omarchy.dropbox {}' "$calls" ||
  fail "plugin enable did not use manifest-default placement"
pass "plugin enable leaves default placement to the registry"

if run_enable omarchy.bar --section right >/dev/null 2>&1; then
  fail "plugin enable accepted placement for a full bar"
fi
pass "plugin enable rejects placement for full bars"

metadata_dir="$TMPDIR/home/.config/omarchy/plugins/acme.agent"
mkdir -p "$metadata_dir"
cat >"$metadata_dir/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"acme.agent","name":"Acme Agent","version":"1.0.0","kinds":[],"entryPoints":{},"agentHarness":{"id":"acme-agent","name":"Acme Agent","install":{"type":"mise","package":"npm:@acme/agent","command":"acme-agent"},"launch":{"mode":"terminal","command":["acme-agent"]}}}
JSON
if run_enable acme.agent >/dev/null 2>&1; then
  fail "plugin enable accepts a metadata-only harness plugin"
fi
pass "plugin enable rejects metadata-only harness plugins"
