#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
call_log="$test_tmp/fc-list-calls"
mkdir -p "$mock_bin"

cat >"$mock_bin/fc-list" <<'SH'
#!/bin/bash

printf '%s\n' "$1" >>"$FC_LIST_CALL_LOG"

case "$1" in
  ":spacing=90")
    printf '%s\n' "Dual Width" "Shared Family" "Omarchy Dual"
    ;;
  ":spacing=100")
    printf '%s\n' "Mono Width" "Shared Family" "Emoji Mono"
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod +x "$mock_bin/fc-list"

actual=$(FC_LIST_CALL_LOG="$call_log" PATH="$mock_bin:$PATH" "$ROOT/bin/omarchy-font-list")
expected=$'Dual Width\nMono Width\nShared Family'

[[ $actual == "$expected" ]] || fail "font list includes fixed-grid font families" "expected:\n$expected\nactual:\n$actual"
pass "font list includes fixed-grid font families"

calls=$(<"$call_log")
expected_calls=$':spacing=90\n:spacing=100'
[[ $calls == "$expected_calls" ]] || fail "font list queries mono and dual spacing" "expected:\n$expected_calls\nactual:\n$calls"
pass "font list queries mono and dual spacing"
