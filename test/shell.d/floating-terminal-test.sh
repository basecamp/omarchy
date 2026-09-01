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

[[ $launch == *"status=\$?"* || $launch == *'status=$?'* ]] || fail "presentation wrapper captures the command status" "$launch"
[[ $launch == *"omarchy-show-done --failed"* ]] || fail "presentation wrapper shows Failed on non-cancel errors" "$launch"
[[ $launch == *"status == 0"* ]] || fail "presentation wrapper shows Done only on success" "$launch"
pass "presentation wrapper distinguishes success, failure, and cancel"
