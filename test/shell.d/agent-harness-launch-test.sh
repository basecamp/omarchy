#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
home="$test_tmp/home"
mock_bin="$test_tmp/bin"
plugin="$home/.config/omarchy/plugins/acme.integration"
agent_file="$home/.config/omarchy/defaults/agent"
argv_log="$test_tmp/argv"
marker="$test_tmp/should-not-exist"
mkdir -p "$plugin" "$mock_bin" "$(dirname "$agent_file")"

cat >"$plugin/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"acme.integration","name":"Acme integration","version":"1.0.0","kinds":[],"entryPoints":{},"agentHarness":{"id":"acme-agent","name":"Acme Agent","install":{"type":"mise","package":"npm:@acme/agent","command":"acme-agent"},"launch":{"mode":"browser","command":["acme-agent","--project={project}"],"promptCommand":["acme-agent","--project={project}","--prompt={prompt}"]}}}
JSON

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$mock_bin/acme-agent" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_ARGV_LOG"
SH
cat >"$mock_bin/omarchy-launch-tui" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_ARGV_LOG"
SH
chmod +x "$mock_bin"/*

export HOME="$home"
export OMARCHY_PATH="$ROOT"
export OMARCHY_TEST_ARGV_LOG="$argv_log"
export PATH="$mock_bin:$ROOT/bin:$PATH"
printf '%s\n' acme-agent >"$agent_file"

project="$test_tmp/project with spaces"
mkdir -p "$project"
prompt=$(printf '$(touch %s); "quoted"\tline\nnext' "$marker")
(
  cd "$project"
  omarchy-agent --prompt "$prompt"
)
[[ ! -e $marker ]] || fail "harness prompt executes shell text"
mapfile -d '' -t argv <"$argv_log"
[[ ${#argv[@]} == 2 && ${argv[0]} == "--project=$project" && ${argv[1]} == "--prompt=$prompt" ]] ||
  fail "browser harness preserves project and prompt as literal argv" "actual: ${argv[*]}"
pass "browser harness substitutes project and hostile prompts without shell evaluation"

jq '.agentHarness.launch.mode = "terminal" | del(.agentHarness.launch.promptCommand)' "$plugin/manifest.json" >"$plugin/updated.json"
mv "$plugin/updated.json" "$plugin/manifest.json"
(
  cd "$project"
  omarchy-agent --prompt "$prompt"
)
mapfile -d '' -t argv <"$argv_log"
[[ ${#argv[@]} == 3 && ${argv[0]} == "--app-id=org.omarchy.agent" && ${argv[1]} == "acme-agent" && ${argv[2]} == "--project=$project" ]] ||
  fail "terminal harness falls back to its command template" "actual: ${argv[*]}"
pass "terminal harness uses argv fallback when promptCommand is omitted"
