#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"
source "$ROOT/default/bash/fns/herdr"

assert_invalid_pane_count() {
  local function_name="$1"
  local count="$2"
  local expected="Usage: $function_name <pane_count> <command>"
  local output status=0

  if [[ $function_name == tsl ]]; then
    output=$(TMUX= bash -c 'source "$1"; tsl "$2" echo' _ "$ROOT/default/bash/fns/tmux" "$count" 2>&1) || status=$?
  else
    output=$(HERDR_PANE_ID= bash -c 'source "$1"; hsl "$2" echo' _ "$ROOT/default/bash/fns/herdr" "$count" 2>&1) || status=$?
  fi

  (( status != 0 )) || fail "$function_name rejects an invalid pane count"
  [[ $output == *"$expected"* ]] || fail "$function_name prints usage for an invalid pane count" "$output"
  pass "$function_name rejects an invalid pane count"
}

assert_invalid_pane_count tsl not-a-number
assert_invalid_pane_count tsl 0
assert_invalid_pane_count hsl not-a-number
assert_invalid_pane_count hsl 0

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
