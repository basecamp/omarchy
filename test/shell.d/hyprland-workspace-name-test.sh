#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
config_file="$tmpdir/shell.json"
bar_log="$tmpdir/bar.log"
notify_log="$tmpdir/notify.log"
mkdir -p "$stub_dir"

# The shell answers listShellConfig with whatever the test put in shell.json.
cat >"$stub_dir/omarchy-shell" <<'STUB'
#!/bin/bash
[[ $1 == "shell" && $2 == "listShellConfig" ]] || exit 1
[[ -n $SHELL_DOWN ]] && exit 1
cat "$SHELL_CONFIG"
STUB

cat >"$stub_dir/omarchy-bar" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$BAR_LOG"
STUB

cat >"$stub_dir/omarchy-plugin-list" <<'STUB'
#!/bin/bash
printf '%s\n' "${PLUGIN_LIST:-[]}"
STUB

cat >"$stub_dir/omarchy-menu-input" <<'STUB'
#!/bin/bash
[[ -n $MENU_CANCELLED ]] && exit 1
printf '%s\n' "$MENU_ANSWER"
STUB

cat >"$stub_dir/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
STUB

chmod +x "$stub_dir"/*

run() {
  SHELL_CONFIG="$config_file" BAR_LOG="$bar_log" NOTIFY_LOG="$notify_log" PATH="$stub_dir:$PATH" \
    "$ROOT/bin/omarchy-hyprland-workspace-name" "$@"
}

reset_logs() {
  : >"$bar_log"
  : >"$notify_log"
}

write_config() {
  printf '%s\n' "$1" >"$config_file"
}

last_bar_call() {
  tail -n 1 "$bar_log"
}

write_config '{"bar":{"layout":{"left":[{"id":"omarchy.menu"},{"id":"omarchy.workspaces","names":{"1":"term"}}],"center":[],"right":[]}}}'

reset_logs
run 2 web
[[ $(last_bar_call) == 'set omarchy.workspaces names {"1":"term","2":"web"} --json' ]] ||
  fail "naming a workspace merges into the existing names" "$(cat "$bar_log")"
pass "naming a workspace merges into the existing names"

reset_logs
run 1 "  two words  "
[[ $(last_bar_call) == 'set omarchy.workspaces names {"1":"two words"} --json' ]] ||
  fail "a name is trimmed and may hold a space" "$(cat "$bar_log")"
pass "a name is trimmed and may hold a space"

reset_logs
run --clear 1
[[ $(last_bar_call) == 'set omarchy.workspaces names {} --json' ]] ||
  fail "clearing removes the name" "$(cat "$bar_log")"
pass "clearing removes the name"

reset_logs
run 1 ""
[[ $(last_bar_call) == 'set omarchy.workspaces names {} --json' ]] ||
  fail "an empty name clears like --clear" "$(cat "$bar_log")"
pass "an empty name clears like --clear"

reset_logs
if run 3 "seventeen chars!!" 2>/dev/null; then
  fail "a name over the limit is refused"
fi
[[ ! -s $bar_log ]] || fail "a refused name writes nothing" "$(cat "$bar_log")"
pass "a name over the limit is refused without writing"

reset_logs
run 3 "sixteen chars ok"
[[ $(last_bar_call) == 'set omarchy.workspaces names {"1":"term","3":"sixteen chars ok"} --json' ]] ||
  fail "a name at the limit is accepted" "$(cat "$bar_log")"
pass "a name at the limit is accepted"

reset_logs
for bad in 0 -1 x 1.5 ""; do
  if run "$bad" web 2>/dev/null; then
    fail "workspace id '$bad' is rejected"
  fi
done
[[ ! -s $bar_log ]] || fail "a rejected id writes nothing" "$(cat "$bar_log")"
pass "only positive whole numbers are workspace ids"

reset_logs
MENU_ANSWER="  mail " run --prompt 4
[[ $(last_bar_call) == 'set omarchy.workspaces names {"1":"term","4":"mail"} --json' ]] ||
  fail "the prompt answer is saved trimmed" "$(cat "$bar_log")"
pass "the prompt answer is saved trimmed"

reset_logs
MENU_CANCELLED=1 run --prompt 4
[[ ! -s $bar_log ]] || fail "a dismissed prompt changes nothing" "$(cat "$bar_log")"
pass "a dismissed prompt changes nothing"

reset_logs
MENU_ANSWER="" run --prompt 1
[[ $(last_bar_call) == 'set omarchy.workspaces names {} --json' ]] ||
  fail "an empty prompt answer clears the name" "$(cat "$bar_log")"
pass "an empty prompt answer clears the name"

reset_logs
if MENU_ANSWER="far too long a workspace name" run --prompt 1 2>/dev/null; then
  fail "an over-long prompt answer fails"
fi
[[ ! -s $bar_log ]] || fail "an over-long prompt answer writes nothing" "$(cat "$bar_log")"
grep -q "at most 16" "$notify_log" || fail "an over-long prompt answer is explained in a notification" "$(cat "$notify_log")"
pass "an over-long prompt answer is refused with a notification"

reset_logs
run --widget local.workspaces 2 web
[[ $(last_bar_call) == 'set local.workspaces names {"2":"web"} --json' ]] ||
  fail "--widget names the entry the bar asked for" "$(cat "$bar_log")"
pass "--widget names the entry the bar asked for"

# A user who cloned the widget has the clone in the bar under its own id. The
# built-in id still reaches it, the way the shell routes calls to clones.
write_config '{"bar":{"layout":{"left":[{"id":"me.workspaces","names":{"5":"chat"}}],"center":[],"right":[]}}}'
reset_logs
PLUGIN_LIST='[{"id":"me.workspaces","enabled":true,"clonedFrom":"omarchy.workspaces"},{"id":"omarchy.workspaces","enabled":false,"clonedFrom":""}]' \
  run 2 web
[[ $(last_bar_call) == 'set me.workspaces names {"5":"chat","2":"web"} --json' ]] ||
  fail "the built-in id resolves to the clone that replaced it" "$(cat "$bar_log")"
pass "the built-in id resolves to the clone that replaced it"

output=$(PLUGIN_LIST='[{"id":"me.workspaces","enabled":true,"clonedFrom":"omarchy.workspaces"}]' run --list)
[[ $output == '{"5":"chat"}' ]] || fail "--list prints the names as JSON" "$output"
pass "--list prints the names as JSON"

write_config '{"bar":{"layout":{"left":[{"id":"omarchy.workspaces","names":{"1":"term","2":7}}],"center":[],"right":[]}}}'
output=$(run --list)
[[ $output == '{"1":"term"}' ]] || fail "--list drops names that are not strings" "$output"
pass "--list drops names that are not strings"

write_config '{}'
reset_logs
run 2 web
[[ $(last_bar_call) == 'set omarchy.workspaces names {"2":"web"} --json' ]] ||
  fail "a user without shell.json still gets the built-in widget named" "$(cat "$bar_log")"
pass "a user without shell.json still gets the built-in widget named"

reset_logs
if SHELL_DOWN=1 run 2 web 2>/dev/null; then
  fail "a stopped shell is an error"
fi
[[ ! -s $bar_log ]] || fail "a stopped shell writes nothing" "$(cat "$bar_log")"
pass "a stopped shell is reported, not written around"
