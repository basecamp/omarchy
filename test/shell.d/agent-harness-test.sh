#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
home="$test_tmp/home"
plugin="$home/.config/omarchy/plugins/acme.integration"
mkdir -p "$plugin"
cat >"$plugin/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"acme.integration","name":"Acme integration","version":"1.0.0","description":"Acme agent integration","kinds":[],"entryPoints":{},"agentHarness":{"id":"acme-agent","name":"Acme Agent","aliases":["acme"],"install":{"type":"mise","package":"npm:@acme/agent","command":"acme-agent"},"launch":{"mode":"browser","command":["acme-agent","open","--project","{project}"],"promptCommand":["acme-agent","open","--project","{project}","{prompt}"]}}}
JSON

HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-plugin-validate" "$plugin"
pass "plugin validation accepts a harness-only manifest"
catalog=$(HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-agent-catalog")
jq -e '.[] | select(.id == "acme-agent" and .firstParty == false and .aliases == ["acme"])' <<<"$catalog" >/dev/null ||
  fail "agent catalog discovers harness metadata from an installed plugin"
pass "agent catalog discovers harness metadata from an installed plugin"

jq '.agentHarness.install.type = "shell"' "$plugin/manifest.json" >"$plugin/invalid.json"
mv "$plugin/invalid.json" "$plugin/manifest.json"
if HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-plugin-validate" "$plugin" >/dev/null 2>&1; then
  fail "plugin validation rejects unsupported harness installation hooks"
fi
catalog=$(HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-agent-catalog")
! jq -e '.[] | select(.id == "acme-agent")' <<<"$catalog" >/dev/null ||
  fail "agent catalog rejects invalid harness metadata"
pass "plugins cannot declare arbitrary harness installation hooks"

jq -e '.[] | select(.id == "hermes" and .firstParty == true and .install.type == "installer")' <<<"$catalog" >/dev/null ||
  fail "agent catalog preserves trusted built-in installer exceptions"
pass "agent catalog preserves trusted built-in installer exceptions"

jq '.agentHarness.install.type = "mise" | .agentHarness.launch.command = ["acme-agent", "{unknown}"]' "$plugin/manifest.json" >"$plugin/invalid.json"
mv "$plugin/invalid.json" "$plugin/manifest.json"
if HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-plugin-validate" "$plugin" >/dev/null 2>&1; then
  fail "plugin validation rejects unknown harness placeholders"
fi
pass "plugins may use only documented harness placeholders"

jq '.agentHarness.launch.command = ["acme-agent", "{project}"] | .agentHarness.aliases = ["afk"]' "$plugin/manifest.json" >"$plugin/invalid.json"
mv "$plugin/invalid.json" "$plugin/manifest.json"
if HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-agent-catalog" "$plugin/manifest.json" >/dev/null 2>&1; then
  fail "agent catalog accepts a harness alias that conflicts with a built-in id"
fi
pass "agent catalog rejects harness identity collisions"
