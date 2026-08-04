#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
agent_file="$test_home/.config/omarchy/defaults/agent"
notification_history="$test_tmp/notification-history"
agent_open_log="$test_tmp/agent-open"
launch_log="$test_tmp/launch"
inline_log="$test_tmp/inline"
mise_log="$test_tmp/mise"
mise_history="$test_tmp/mise-history"
stub_log="$test_tmp/stubs"
terminal_log="$test_tmp/terminal"
mkdir -p "$mock_bin" "$test_home"

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_NOTIFICATION_HISTORY"
SH

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
[[ $1 == ${OMARCHY_TEST_MISSING_COMMAND:-} ]]
SH

cat >"$mock_bin/omarchy-launch-tui" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_AGENT_LAUNCH_LOG"
SH

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_AGENT_TERMINAL_LOG"
SH

cat >"$mock_bin/opencode" <<'SH'
#!/bin/bash
printf '%s\0' opencode "$@" >"$OMARCHY_TEST_AGENT_INLINE_LOG"
SH

cat >"$mock_bin/omarchy-mise-install" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_STUB_LOG"
SH

cat >"$mock_bin/mise" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_MISE_LOG"
printf '%s\n' "$*" >>"$OMARCHY_TEST_MISE_HISTORY"

if [[ $1 == "where" ]]; then
  [[ ${OMARCHY_TEST_AGENT_INSTALLED:-false} == "true" ]]
  exit
fi

[[ ${OMARCHY_TEST_MISE_FAIL:-false} != "true" ]]
SH

cat >"$mock_bin/omarchy-test-noop" <<'SH'
#!/bin/bash
exit 0
SH

for command in gum hyprctl omarchy-webapp-remove-all omarchy-tui-remove-all omarchy-pkg-drop; do
  ln -s omarchy-test-noop "$mock_bin/$command"
done

chmod +x "$mock_bin"/*

export HOME="$test_home"
export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_TEST_NOTIFICATION_HISTORY="$notification_history"
export OMARCHY_TEST_AGENT_OPEN_LOG="$agent_open_log"
export OMARCHY_TEST_AGENT_LAUNCH_LOG="$launch_log"
export OMARCHY_TEST_AGENT_INLINE_LOG="$inline_log"
export OMARCHY_TEST_MISE_LOG="$mise_log"
export OMARCHY_TEST_MISE_HISTORY="$mise_history"
export OMARCHY_TEST_STUB_LOG="$stub_log"
export OMARCHY_TEST_AGENT_TERMINAL_LOG="$terminal_log"

grok_package="npm:@xai-official/grok"
omp_package="github:can1357/oh-my-pi"
crush_package="crush"

assert_lazy_stub() {
  local package=$1
  local command=$2

  : >"$mise_history"
  "$ROOT/bin/omarchy-mise-install" "$package" "$command"
  "$test_home/.local/bin/$command" --version
  mapfile -t mise_calls <"$mise_history"

  [[ ${mise_calls[0]} == "use -g $package" && ${mise_calls[1]} == "x $package -- $command --version" ]] ||
    fail "$command lazy stub preserves its mise package"
}

assert_lazy_stub "$grok_package" grok
assert_lazy_stub "$omp_package" omp
assert_lazy_stub "$crush_package" crush
pass "custom agent lazy stubs preserve their mise packages"

source "$ROOT/install/user/mise.sh"
grep -Fx "$grok_package grok" "$stub_log" >/dev/null || fail "user setup creates the Grok lazy stub"
grep -Fx "$omp_package omp" "$stub_log" >/dev/null || fail "user setup creates the Oh My Pi lazy stub"
grep -Fx "$crush_package" "$stub_log" >/dev/null || fail "user setup creates the Crush lazy stub"
pass "user setup creates the custom agent lazy stubs"

: >"$stub_log"
source "$ROOT/migrations/1785617047.sh" >/dev/null
grep -Fx "$omp_package omp" "$stub_log" >/dev/null || fail "Oh My Pi migration creates a working lazy stub"

: >"$stub_log"
source "$ROOT/migrations/1785846769.sh" >/dev/null
grep -Fx "$omp_package omp" "$stub_log" >/dev/null || fail "agent migration repairs the Oh My Pi lazy stub"
grep -Fx "$grok_package grok" "$stub_log" >/dev/null || fail "agent migration creates the Grok lazy stub"
grep -Fx "$crush_package" "$stub_log" >/dev/null || fail "agent migration creates the Crush lazy stub"

mkdir -p "$test_home/.local/state/omarchy"
touch "$test_home/.local/state/omarchy/preinstalls-removed"
"$ROOT/bin/omarchy-mise-install" oh-my-pi omp
: >"$stub_log"
source "$ROOT/migrations/1785617047.sh" >/dev/null
source "$ROOT/migrations/1785846769.sh" >/dev/null
[[ ! -s $stub_log ]] || fail "agent migrations respect the preinstall opt-out"
[[ ! -e $test_home/.local/bin/omp ]] || fail "agent migration removes the obsolete Oh My Pi wrapper after opt-out"
rm "$test_home/.local/state/omarchy/preinstalls-removed"
pass "agent migrations install working wrappers without overriding the preinstall opt-out"

omarchy-remove-preinstalls >/dev/null
for command in omp grok crush; do
  [[ ! -e $test_home/.local/bin/$command ]] || fail "Remove Preinstalls deletes the $command lazy stub"
done
pass "Remove Preinstalls deletes every optional agent lazy stub"

[[ $(omarchy-default-agent) == "opencode" ]] || fail "default agent falls back to OpenCode"
pass "default agent falls back to OpenCode"

omarchy-launch-agent
mapfile -d '' -t launch_args <"$launch_log"
[[ ${#launch_args[@]} == 1 && ${launch_args[0]} == "opencode" ]] ||
  fail "agent launcher falls back to OpenCode before a default is selected"
pass "agent launcher falls back to OpenCode before a default is selected"

source "$ROOT/default/bash/aliases"
[[ $(alias a) == "alias a='omarchy-launch-agent --inline'" ]] ||
  fail "terminal alias launches the default agent inline"
pass "terminal alias launches the default agent inline"

grep -Fq 'o.bind("SUPER + SHIFT + CTRL + A", "Agent", "omarchy-launch-agent")' \
  "$ROOT/default/hypr/bindings/utilities.lua" ||
  fail "agent launcher has a keyboard shortcut"
pass "agent launcher has a keyboard shortcut"

cat >"$mock_bin/omarchy-launch-agent" <<'SH'
#!/bin/bash
printf '%s\0' omarchy-launch-agent "$@" >"$OMARCHY_TEST_AGENT_OPEN_LOG"
SH
chmod +x "$mock_bin/omarchy-launch-agent"
hash -r

declare -A expected_agents=(
  [pi]="pi"
  [omp]="omp"
  [oh-my-pi]="omp"
  [opencode]="opencode"
  [open-code]="opencode"
  [claude]="claude"
  [claude-code]="claude"
  [codex]="codex"
  [crush]="crush"
  [grok]="grok"
  [gemini]="gemini"
  [gemini-cli]="gemini"
  [copilot]="copilot"
  [github-copilot]="copilot"
)

declare -A expected_packages=(
  [pi]="pi"
  [omp]="$omp_package"
  [opencode]="opencode"
  [claude]="claude"
  [codex]="codex"
  [crush]="$crush_package"
  [grok]="$grok_package"
  [gemini]="gemini"
  [copilot]="copilot"
)

for selection in "${!expected_agents[@]}"; do
  expected=${expected_agents[$selection]}
  : >"$agent_open_log"
  OMARCHY_TEST_AGENT_INSTALLED=true omarchy-default-agent "$selection"
  [[ $(omarchy-default-agent) == $expected ]] || fail "default agent canonicalizes $selection"

  mapfile -d '' -t mise_args <"$mise_log"
  [[ ${mise_args[0]} == "use" && ${mise_args[1]} == "-g" && ${mise_args[2]} == ${expected_packages[$expected]} ]] ||
    fail "default agent installs $selection globally through mise"

  mapfile -d '' -t agent_open_args <"$agent_open_log"
  [[ ${#agent_open_args[@]} == 1 && ${agent_open_args[0]} == "omarchy-launch-agent" ]] ||
    fail "default agent opens $selection after selecting it"
done
pass "default agent selects and opens every supported provider and alias"
[[ -f $agent_file && ! -e $test_home/.local/state/omarchy/defaults/agent ]] ||
  fail "default agent stores its selection in Omarchy user config"
pass "default agent stores its selection in Omarchy user config"

OMARCHY_TEST_AGENT_INSTALLED=true omarchy-default-agent pi
: >"$notification_history"
: >"$agent_open_log"
: >"$terminal_log"
omarchy-default-agent github-copilot
mapfile -d '' -t terminal_args <"$terminal_log"
[[ ${terminal_args[0]} == "omarchy-default-agent" && ${terminal_args[1]} == "--install" && ${terminal_args[2]} == "copilot" ]] ||
  fail "missing agent installation opens in a terminal"
[[ ! -s $notification_history ]] || fail "missing agent installation skips notifications"
[[ ! -s $agent_open_log ]] || fail "missing agent installation waits to open the agent"
[[ $(omarchy-default-agent) == "pi" ]] || fail "missing agent installation waits to change the selection"

omarchy-default-agent --install github-copilot >"$test_tmp/install-output"
mapfile -d '' -t mise_args <"$mise_log"
[[ ${mise_args[0]} == "use" && ${mise_args[1]} == "-g" && ${mise_args[2]} == "copilot" ]] ||
  fail "visible agent installation activates the provider globally through mise"
[[ $(omarchy-default-agent) == "copilot" ]] || fail "visible agent installation changes the selection after mise succeeds"
[[ ! -s $notification_history ]] || fail "visible agent installation leaves progress to the terminal"
[[ $(<"$test_tmp/install-output") == $'\033[2J\033[3J\033[H' ]] ||
  fail "visible agent installation clears its terminal before opening the agent"
mapfile -d '' -t agent_open_args <"$agent_open_log"
[[ ${#agent_open_args[@]} == 2 && ${agent_open_args[0]} == "omarchy-launch-agent" && ${agent_open_args[1]} == "--inline" ]] ||
  fail "newly installed agent opens in the installation terminal"
pass "missing agents install visibly and open in the same terminal"

: >"$notification_history"
: >"$agent_open_log"
: >"$terminal_log"
OMARCHY_TEST_AGENT_INSTALLED=true omarchy-default-agent github-copilot
[[ ! -s $terminal_log ]] || fail "installed agent selection skips the terminal"
[[ ! -s $notification_history ]] || fail "installed agent selection skips notifications"
mapfile -d '' -t mise_args <"$mise_log"
[[ ${mise_args[0]} == "use" && ${mise_args[1]} == "-g" && ${mise_args[2]} == "copilot" ]] ||
  fail "default agent still activates an installed provider globally through mise"
mapfile -d '' -t agent_open_args <"$agent_open_log"
[[ ${#agent_open_args[@]} == 1 && ${agent_open_args[0]} == "omarchy-launch-agent" ]] ||
  fail "installed agent opens in a new terminal after selection"
pass "installed agents select and open without notifications"

: >"$agent_open_log"
if omarchy-default-agent unsupported >"$test_tmp/invalid-output" 2>&1; then
  fail "default agent rejects unsupported providers"
fi
grep -F "Usage: omarchy-default-agent" "$test_tmp/invalid-output" >/dev/null ||
  fail "default agent explains supported providers"
[[ $(omarchy-default-agent) == "copilot" ]] || fail "invalid selection preserves the current default agent"
[[ ! -s $agent_open_log ]] || fail "invalid selection does not open an agent"
pass "default agent rejects unsupported providers without changing the selection"

: >"$notification_history"
: >"$agent_open_log"
if OMARCHY_TEST_MISE_FAIL=true omarchy-default-agent --install codex >"$test_tmp/install-failure-output" 2>&1; then
  fail "default agent rejects a failed mise installation"
fi
[[ $(omarchy-default-agent) == "copilot" ]] || fail "failed installation preserves the current default agent"
grep -F "Could not install Codex with mise" "$test_tmp/install-failure-output" >/dev/null ||
  fail "default agent reports a failed mise installation in the terminal"
[[ ! -s $notification_history ]] || fail "failed visible agent installation skips notifications"
[[ ! -s $agent_open_log ]] || fail "failed installation does not open an agent"
pass "default agent opens only after mise installs the provider"

: >"$notification_history"
: >"$agent_open_log"
if OMARCHY_TEST_AGENT_INSTALLED=true OMARCHY_TEST_MISE_FAIL=true omarchy-default-agent codex >"$test_tmp/setup-failure-output" 2>&1; then
  fail "default agent rejects a failed mise activation"
fi
[[ $(omarchy-default-agent) == "copilot" ]] || fail "failed activation preserves the current default agent"
grep -F "Could not set Codex as the default coding agent" "$test_tmp/setup-failure-output" >/dev/null ||
  fail "default agent reports a failed activation for an installed provider"
[[ ! -s $notification_history ]] || fail "failed activation skips notifications"
[[ ! -s $agent_open_log ]] || fail "failed activation does not open an agent"
pass "default agent reports mise failures without notifications"

rm "$mock_bin/omarchy-launch-agent"
hash -r

assert_launch() {
  local agent=$1
  shift
  local expected=("$@")

  printf '%s\n' "$agent" >"$agent_file"
  omarchy-launch-agent "Review this" project
  mapfile -d '' -t actual <"$launch_log"

  (( ${#actual[@]} == ${#expected[@]} )) ||
    fail "$agent launch has the expected argument count" "expected: ${expected[*]}\nactual: ${actual[*]}"

  for ((index = 0; index < ${#expected[@]}; index++)); do
    [[ ${actual[$index]} == ${expected[$index]} ]] ||
      fail "$agent launch forwards the interactive prompt" "expected: ${expected[*]}\nactual: ${actual[*]}"
  done
}

assert_launch pi pi -- "Review this project"
assert_launch omp omp -- "Review this project"
assert_launch opencode opencode --prompt "Review this project"
assert_launch claude claude -- "Review this project"
assert_launch codex codex -- "Review this project"
assert_launch crush crush run "Review this project"
assert_launch grok grok -- "Review this project"
assert_launch gemini gemini --prompt-interactive "Review this project"
assert_launch copilot copilot --interactive "Review this project"
pass "agent launcher adapts initial prompts for every supported agent"

printf '%s\n' "opencode" >"$agent_file"
omarchy-launch-agent
mapfile -d '' -t launch_args <"$launch_log"
[[ ${#launch_args[@]} == 1 && ${launch_args[0]} == "opencode" ]] ||
  fail "agent launcher starts the selected agent without an initial prompt"
pass "agent launcher starts the selected agent without an initial prompt"

omarchy-launch-agent --inline "Review this project"
mapfile -d '' -t inline_args <"$inline_log"
[[ ${inline_args[0]} == "opencode" && ${inline_args[1]} == "--prompt" && ${inline_args[2]} == "Review this project" ]] ||
  fail "inline agent launcher runs in the current terminal"
pass "inline agent launcher runs in the current terminal"

printf '%s\n' "missing" >"$agent_file"
if OMARCHY_TEST_MISSING_COMMAND=missing omarchy-launch-agent >"$test_tmp/missing-output" 2>&1; then
  fail "agent launcher rejects a missing default command"
fi
grep -F "missing is not installed" "$test_tmp/missing-output" >/dev/null ||
  fail "agent launcher explains when the default command is missing"
pass "agent launcher reports a missing default command"
