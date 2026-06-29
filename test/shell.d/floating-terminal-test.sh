#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/hyprctl" <<'SCRIPT'
#!/bin/bash
case "$1" in
  activeworkspace)
    printf '{"id":2,"name":"2"}\n'
    ;;
  dispatch)
    printf '%s\n' "$2" >>"$TEST_LOG"
    ;;
esac
SCRIPT
chmod +x "$tmp_dir/hyprctl"

cat >"$tmp_dir/jq" <<'SCRIPT'
#!/bin/bash
cat >/dev/null
printf '2\n'
SCRIPT
chmod +x "$tmp_dir/jq"

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir:$ROOT/bin:$PATH"
export HYPRLAND_INSTANCE_SIGNATURE=test

"$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "echo hello"

dispatch=$(<"$TEST_LOG")
[[ $dispatch == *'workspace = "2"'* ]] || fail "floating terminal targets active workspace" "$dispatch"
[[ $dispatch == *"xdg-terminal-exec --app-id=org.omarchy.terminal"* ]] || fail "floating terminal dispatch launches Omarchy terminal" "$dispatch"
pass "floating terminal targets active workspace"

: >"$TEST_LOG"
OMARCHY_LAUNCH_WORKSPACE=7 "$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "echo hello"

dispatch=$(<"$TEST_LOG")
[[ $dispatch == *'workspace = "7"'* ]] || fail "floating terminal honors explicit launch workspace" "$dispatch"
pass "floating terminal honors explicit launch workspace"
