#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/setsid" <<'SCRIPT'
#!/bin/bash
printf 'browser=%s\n' "${BROWSER:-UNSET}" >"$TEST_LOG"
printf 'args=%s\n' "$*" >>"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/setsid"

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir:$ROOT/bin:$PATH"

env -u BROWSER "$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "echo hello"

launch=$(<"$TEST_LOG")
[[ $launch == *"xdg-terminal-exec --app-id=org.omarchy.terminal"* ]] || fail "floating terminal launches Omarchy terminal" "$launch"
grep -Fxq 'browser=omarchy-launch-browser' <<<"$launch" || fail "floating terminal hands the terminal Omarchy's BROWSER default" "$launch"
pass "floating terminal hands the terminal Omarchy's browser default"

BROWSER=custom-browser "$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "echo hello"
launch=$(<"$TEST_LOG")
grep -Fxq 'browser=custom-browser' <<<"$launch" || fail "floating terminal preserves a user BROWSER override" "$launch"
pass "floating terminal preserves a user BROWSER override"
