#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"
source "$ROOT/default/bash/fns/herdr"

test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

mkdir -p "$test_dir/first project's files" "$test_dir/second project"
log="$test_dir/herdr.log"

herdr() {
  if [[ $1 == "workspace" ]]; then
    return
  elif [[ $1 == "tab" ]]; then
    printf '{"result":{"root_pane":{"pane_id":"new-pane"}}}\n'
  elif [[ $1 == "pane" && $2 == "run" ]]; then
    printf '%s\n' "$4" >>"$log"
  fi
}

export HERDR_PANE_ID="current-pane"
export HERDR_WORKSPACE_ID="workspace"

cd "$test_dir"
hdlm "codex --flag='value with spaces'" "claude --model sonnet"

mapfile -t commands <"$log"

expected_first=$(printf 'cd %q && hdl %q %q' \
  "$test_dir/first project's files" "codex --flag='value with spaces'" "claude --model sonnet")
expected_second=$(printf 'hdl %q %q' "codex --flag='value with spaces'" "claude --model sonnet")

[[ ${commands[0]} == "$expected_first" ]] || fail "hdlm safely quotes its first queued command"
pass "hdlm safely quotes its first queued command"

[[ ${commands[1]} == "$expected_second" ]] || fail "hdlm preserves agent argument boundaries"
pass "hdlm preserves agent argument boundaries"

: >"$log"
hdlm "codex --quiet"
mapfile -t commands <"$log"
expected_first=$(printf 'cd %q && hdl %q' "$test_dir/first project's files" "codex --quiet")

[[ ${commands[0]} == "$expected_first" ]] || fail "hdlm omits an absent second agent argument"
pass "hdlm omits an absent second agent argument"

: >"$log"
hdlm
mapfile -t commands <"$log"
expected_first=$(printf 'cd %q && hdl' "$test_dir/first project's files")

[[ ${commands[0]} == "$expected_first" ]] || fail "hdlm without agents queues a bare hdl"
pass "hdlm without agents queues a bare hdl"

export HERDR_TAB_ID="tab"
: >"$log"
hdl
mapfile -t commands <"$log"

[[ ${commands[0]} == "omarchy-agent --inline" ]] || fail "hdl without an agent runs the default agent"
pass "hdl without an agent runs the default agent"

: >"$log"
hdl "codex --quiet"
mapfile -t commands <"$log"

[[ ${commands[0]} == "codex --quiet" ]] || fail "hdl with an agent runs that agent"
pass "hdl with an agent runs that agent"

for flag in -h --help; do
  [[ $(hdl "$flag") == "Usage: hdl "* ]] || fail "hdl $flag prints usage"
  pass "hdl $flag prints usage"

  [[ $(hdlm "$flag") == "Usage: hdlm "* ]] || fail "hdlm $flag prints usage"
  pass "hdlm $flag prints usage"
done
