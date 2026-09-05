#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT

qconsole="$ROOT/default/hypr/qconsole.lua"
scratchpad_config="$ROOT/config/herdr/scratchpad.toml"
launcher="$ROOT/bin/omarchy-scratchpad-agent"

qconsole_source=$(<"$qconsole")
[[ $qconsole_source == *'HERDR_CONFIG_PATH="$HOME/.config/herdr/scratchpad.toml"'* ]] ||
  fail "scratchpad starts Herdr with its dedicated profile"
[[ $qconsole_source == *'herdr --session scratchpad'* ]] ||
  fail "scratchpad starts a named Herdr session"
[[ $qconsole_source == *'monitor.height / monitor.scale'* ]] ||
  fail "scratchpad keeps height-based sizing"
[[ $qconsole_source == *'style = "slide top"'* ]] ||
  fail "scratchpad keeps its top-entry animation"
[[ $qconsole_source == *'style = "slide bottom"'* ]] ||
  fail "scratchpad keeps its top-exit animation"
pass "scratchpad keeps its default geometry and animation"

config_source=$(<"$scratchpad_config")
for setting in \
  'default_shell = "omarchy-scratchpad-agent"' \
  'shell_mode = "non_login"' \
  'sidebar_collapsed_mode = "hidden"' \
  'hide_tab_bar_when_single_tab = true' \
  'pane_borders = false' \
  'pane_outer_borders = false' \
  'pane_gaps = false' \
  'pane_scrollbars = false' \
  'delivery = "system"' \
  'delay_seconds = 1' \
  'enabled = true' \
  'resume_agents_on_restore = true'; do
  [[ $config_source == *"$setting"* ]] || fail "scratchpad profile sets $setting"
done
pass "scratchpad profile configures a minimal UI, notifications, sound, and restore"

test_home="$test_tmp/home"
mkdir -p "$test_home"
HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
  bash -euo pipefail "$ROOT/migrations/1788016185.sh" >/dev/null
[[ -f $test_home/.config/herdr/scratchpad.toml ]] ||
  fail "migration seeds the scratchpad profile"

printf '%s\n' custom >"$test_home/.config/herdr/scratchpad.toml"
HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
  bash -euo pipefail "$ROOT/migrations/1788016185.sh" >/dev/null
[[ $(<"$test_home/.config/herdr/scratchpad.toml") == custom ]] ||
  fail "migration preserves an existing scratchpad profile"
pass "migration seeds the profile without replacing customization"

mock_bin="$test_tmp/bin"
agent_log="$test_tmp/agent.log"
shell_log="$test_tmp/shell.log"
mkdir -p "$mock_bin"

cat >"$mock_bin/herdr" <<'SH'
#!/bin/bash
if [[ ${OMARCHY_TEST_RESTORED:-false} == true ]]; then
  printf '%s\n' '{"result":{"pane":{"agent_session":{"agent":"pi"}}}}'
else
  printf '%s\n' '{"result":{"pane":{"agent_session":null}}}'
fi
SH

cat >"$mock_bin/omarchy-agent" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_AGENT_LOG"
SH

cat >"$mock_bin/test-shell" <<'SH'
#!/bin/bash
printf '%s\n' started >"$OMARCHY_TEST_SHELL_LOG"
SH

chmod +x "$mock_bin"/*

: >"$agent_log"
HOME="$test_home" PATH="$mock_bin:$PATH" HERDR_PANE_ID=pane-new \
  OMARCHY_TEST_AGENT_LOG="$agent_log" OMARCHY_TEST_RESTORED=false \
  "$launcher"
mapfile -d '' -t agent_args <"$agent_log"
[[ ${agent_args[*]} == "--inline" ]] || fail "new scratchpad panes launch the default agent inline"
pass "new scratchpad panes launch the default agent inline"

: >"$agent_log"
rm -f "$shell_log"
HOME="$test_home" PATH="$mock_bin:$PATH" SHELL="$mock_bin/test-shell" HERDR_PANE_ID=pane-restored \
  OMARCHY_TEST_AGENT_LOG="$agent_log" OMARCHY_TEST_SHELL_LOG="$shell_log" \
  OMARCHY_TEST_RESTORED=true "$launcher"
[[ ! -s $agent_log ]] || fail "restored scratchpad panes do not start a second agent"
[[ -f $shell_log ]] || fail "restored scratchpad panes leave a shell for Herdr resume"
pass "restored scratchpad panes leave Herdr's resume command untouched"
