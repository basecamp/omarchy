#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# The point of lua_script is that a raising script returns nonzero, which
# `lua <<'LUA'` does not. Nothing else covers that: every converted suite runs
# scripts that succeed, so the false-green behaviour could come back unnoticed.
printf 'print("hello")\n' >"$tmpdir/hello.lua"
output=$(lua_script <"$tmpdir/hello.lua") || fail "a succeeding Lua script returns success"
[[ $output == "hello" ]] || fail "lua_script passes stdout through" "actual: $output"
pass "lua_script passes stdout through and returns success"

status=0
lua_script >/dev/null 2>&1 <<'LUA' || status=$?
assert(false)
LUA
(( status != 0 )) || fail "a failing Lua assertion returns nonzero"
pass "lua_script propagates a failing Lua assertion"

status=0
lua_script >/dev/null 2>&1 <<'LUA' || status=$?
error("boom")
LUA
(( status != 0 )) || fail "a raised Lua error returns nonzero"
pass "lua_script propagates a raised Lua error"

# run_lua_test reports one assertion, so its failure path exits; run it in a
# subshell to observe the exit status rather than inherit it.
(run_lua_test "a subshell assertion that should not be reported" >/dev/null 2>&1 <<'LUA'
assert(false)
LUA
)
(( $? != 0 )) || fail "run_lua_test fails on a failing Lua assertion"
pass "run_lua_test fails on a failing Lua assertion"

run_lua_test "run_lua_test reports a passing Lua script" <<'LUA'
assert(1 + 1 == 2)
LUA

# The suites run these scripts under a deliberately stripped PATH to prove a
# missing binary is detected, so the helper cannot reach for anything but the
# interpreter itself.
lua_bin=$(command -v lua)
bare_bin="$tmpdir/bare-bin"
mkdir -p "$bare_bin"
ln -s "$lua_bin" "$bare_bin/lua"
printf 'print("bare")\n' >"$tmpdir/bare.lua"
bare=$(PATH="$bare_bin" lua_script <"$tmpdir/bare.lua") ||
  fail "lua_script runs with only the interpreter on PATH"
[[ $bare == "bare" ]] || fail "lua_script runs with only the interpreter on PATH" "actual: $bare"
pass "lua_script needs nothing on PATH but the interpreter"
