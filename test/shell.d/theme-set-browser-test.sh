#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
call_log="$test_tmp/browser-calls.log"
mkdir -p "$stub_bin" "$test_tmp/home"

cat >"$stub_bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
[[ $1 == "brave" || $1 == "brave-origin" ]]
STUB

cat >"$stub_bin/omarchy-theme-set-browser-policy" <<'STUB'
#!/bin/bash
exit 0
STUB

cat >"$stub_bin/pgrep" <<'STUB'
#!/bin/bash
if [[ ${BROWSER_SCENARIO:-origin} == "origin" ]]; then
  [[ $* == "-x brave" || $* == "-f /opt/brave-origin-bin/" ]]
else
  [[ $* == "-f /opt/brave-bin/" ]]
fi
STUB

cat >"$stub_bin/brave" <<'STUB'
#!/bin/bash
printf 'brave\n' >>"$BROWSER_CALL_LOG"
STUB

cat >"$stub_bin/brave-origin" <<'STUB'
#!/bin/bash
printf 'brave-origin\n' >>"$BROWSER_CALL_LOG"
STUB

cat >"$stub_bin/tee" <<'STUB'
#!/bin/bash
cat >/dev/null
STUB

chmod +x "$stub_bin"/*

HOME="$test_tmp/home" OMARCHY_PATH="$ROOT" BROWSER_CALL_LOG="$call_log" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-theme-set-browser"

[[ ! -e $call_log ]] || ! grep -Fxq brave "$call_log" ||
  fail "Brave refresh ignores Brave Origin processes"
grep -Fxq brave-origin "$call_log" ||
  fail "Brave Origin refresh still matches its binary path"
pass "Brave refresh distinguishes Brave from Brave Origin"

: >"$call_log"
HOME="$test_tmp/home" OMARCHY_PATH="$ROOT" BROWSER_CALL_LOG="$call_log" BROWSER_SCENARIO=regular \
  PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-theme-set-browser"

grep -Fxq brave "$call_log" ||
  fail "Brave refresh still matches its binary path"
[[ $(wc -l <"$call_log") -eq 1 ]] ||
  fail "Regular Brave does not refresh another Brave package"
pass "Brave refresh still detects regular Brave"
