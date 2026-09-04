#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/setsid" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/setsid"

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir:$ROOT/bin:$PATH"

"$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "echo hello"

launch=$(<"$TEST_LOG")
[[ $launch == *"xdg-terminal-exec --app-id=org.omarchy.terminal"* ]] || fail "floating terminal launches Omarchy terminal" "$launch"
pass "floating terminal launches Omarchy terminal"

# Ctrl-C is 130; every other non-zero used to be presented as success.
[[ $launch == *'if (( status == 0 )); then omarchy-show-done;'* ]] ||
  fail "presentation wrapper shows Done only after a successful command" "$launch"
[[ $launch == *'elif (( status != 130 )); then'* ]] ||
  fail "presentation wrapper waits on failure instead of closing immediately" "$launch"
if [[ $launch == *'$? != 130'* ]]; then
  fail "presentation wrapper does not treat a non-zero exit as success" "$launch"
fi
pass "presentation wrapper shows Done only after a successful command"
