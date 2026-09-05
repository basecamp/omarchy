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

mkdir -p "$home/.config/omarchy/plugins/broken.integration"
printf '%s\n' '"not a manifest object"' >"$home/.config/omarchy/plugins/broken.integration/manifest.json"
catalog=$(HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-agent-catalog")
jq -e '.[] | select(.id == "acme-agent")' <<<"$catalog" >/dev/null ||
  fail "agent catalog ignores a non-object installed manifest"
pass "agent catalog ignores non-object installed manifests"

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

jq '.agentHarness.install.type = "mise" | .agentHarness.install.package = "--remove=node"' "$plugin/manifest.json" >"$plugin/invalid.json"
mv "$plugin/invalid.json" "$plugin/manifest.json"
if HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-plugin-validate" "$plugin" >/dev/null 2>&1; then
  fail "plugin validation rejects mise package options"
fi
pass "plugins cannot pass options to mise"

jq '.agentHarness.install.type = "mise" | .agentHarness.launch.command = ["acme-agent", "{unknown}"]' "$plugin/manifest.json" >"$plugin/invalid.json"
mv "$plugin/invalid.json" "$plugin/manifest.json"
if HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-plugin-validate" "$plugin" >/dev/null 2>&1; then
  fail "plugin validation rejects unknown harness placeholders"
fi
pass "plugins may use only documented harness placeholders"

jq '.agentHarness.install.package = "npm:@acme/agent" | .agentHarness.launch.command = ["acme-agent", "{project}"] | .agentHarness.aliases = ["afk"]' "$plugin/manifest.json" >"$plugin/invalid.json"
mv "$plugin/invalid.json" "$plugin/manifest.json"
if HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-agent-catalog" "$plugin/manifest.json" >/dev/null 2>&1; then
  fail "agent catalog accepts a harness alias that conflicts with a built-in id"
fi
pass "agent catalog rejects harness identity collisions"

for alias in 'bad..alias' $'bad\nalias'; do
  jq --arg alias "$alias" '.agentHarness.aliases = [$alias]' "$plugin/manifest.json" >"$plugin/invalid.json"
  mv "$plugin/invalid.json" "$plugin/manifest.json"
  if HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-plugin-validate" "$plugin" >/dev/null 2>&1; then
    fail "plugin validation accepts an invalid harness alias" "$alias"
  fi
  catalog=$(HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-agent-catalog")
  if jq -e '.[] | select(.id == "acme-agent")' <<<"$catalog" >/dev/null; then
    fail "agent catalog accepts an invalid harness alias" "$alias"
  fi
done
pass "harness aliases use the same identity rules as ids"

jq '.agentHarness.aliases = ["acme"]' "$plugin/manifest.json" >"$plugin/valid.json"
mv "$plugin/valid.json" "$plugin/manifest.json"
second_plugin="$home/.config/omarchy/plugins/example.integration"
mkdir -p "$second_plugin"
jq '.id = "example.integration" | .agentHarness.id = "example-agent" | .agentHarness.aliases = ["acme"]' "$plugin/manifest.json" >"$second_plugin/manifest.json"
HOME="$home" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-agent-catalog" >"$test_tmp/catalog.json" 2>"$test_tmp/catalog.stderr"
jq -e '[.[] | select(.id == "acme-agent" or .id == "example-agent")] | length == 1' "$test_tmp/catalog.json" >/dev/null ||
  fail "agent catalog does not choose one existing conflicting harness deterministically"
grep -Fq 'ignoring conflicting installed harness' "$test_tmp/catalog.stderr" ||
  fail "agent catalog does not warn about existing harness collisions"
pass "agent catalog warns while deterministically resolving existing collisions"
