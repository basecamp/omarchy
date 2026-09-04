#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Handing a heredoc to lua with no script argument runs it as a REPL: an error
# is printed and the interpreter still exits 0, so assertions written inside one
# cannot fail their test. Passing an explicit - reads the same heredoc as a
# script, where an error is an error.
repl_lua=$(rg -l -P 'lua[[:space:]]+<<' "$SHELL_TEST_DIR" || true)
[[ -z $repl_lua ]] || fail "shell tests read Lua as a script rather than a REPL" "$repl_lua"
pass "shell tests read Lua as a script rather than a REPL"
