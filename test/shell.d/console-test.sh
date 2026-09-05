#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
console_file="$test_home/.config/omarchy/defaults/console"
run_log="$test_tmp/run"
notification_history="$test_tmp/notification-history"
mkdir -p "$mock_bin" "$test_home"

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_NOTIFICATION_HISTORY"
SH

# Whatever the console is pointed at reports itself rather than opening a window.
for command in omarchy-agent omarchy-launch-terminal omarchy-launch-tui; do
  cat >"$mock_bin/$command" <<SH
#!/bin/bash
printf '%s\0' $command "\$@" >"\$OMARCHY_TEST_CONSOLE_RUN_LOG"
SH
done

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
exec "$@"
SH

chmod +x "$mock_bin"/*

export HOME="$test_home"
export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_TEST_NOTIFICATION_HISTORY="$notification_history"
export OMARCHY_TEST_CONSOLE_RUN_LOG="$run_log"

ran() {
  mapfile -d '' -t run_args <"$run_log"
  printf '%s' "${run_args[*]}"
}

[[ -z $(omarchy-default-console) ]] || fail "the console is unset until it is pointed somewhere"
pass "the console is unset until it is pointed somewhere"

# Omarchy ships the console as the agent's home, so an unset console is still
# one: the setting is what to run *instead*.
: >"$run_log"
omarchy-launch-console
[[ $(ran) == "omarchy-agent" ]] || fail "an unset console runs the coding agent" "$(ran)"
[[ ! -s $notification_history ]] || fail "an unset console reports nothing"
pass "an unset console runs the coding agent"

omarchy-default-console terminal
[[ $(omarchy-default-console) == "omarchy-launch-terminal" ]] ||
  fail "terminal is shorthand for the terminal launcher" "$(omarchy-default-console)"
: >"$run_log"
omarchy-launch-console
[[ $(ran) == "omarchy-launch-terminal" ]] || fail "a console set to a terminal runs one" "$(ran)"
pass "a console set to a terminal runs one"

mapfile -d '' -t notified <"$notification_history"
[[ ${notified[*]} == *"a terminal"* ]] || fail "choosing what the console runs says so" "${notified[*]}"
pass "choosing what the console runs says so"

# Anything else is the command, arguments and all — a TUI needs the terminal
# wrapper named around it to be seen, and that is the caller's to pass.
omarchy-default-console omarchy-launch-tui btop
[[ $(omarchy-default-console) == "omarchy-launch-tui btop" ]] ||
  fail "the console takes any command" "$(omarchy-default-console)"
: >"$run_log"
omarchy-launch-console
[[ $(ran) == "omarchy-launch-tui btop" ]] || fail "the console runs the command it was given" "$(ran)"
pass "the console runs the command it was given"

omarchy-default-console agent
[[ $(omarchy-default-console) == "omarchy-agent" ]] ||
  fail "agent is shorthand for the coding agent" "$(omarchy-default-console)"
: >"$run_log"
omarchy-launch-console
[[ $(ran) == "omarchy-agent" ]] || fail "a console handed back to the agent runs it" "$(ran)"
pass "a console handed back to the agent runs it"

[[ -f $console_file ]] || fail "the console selection lives in Omarchy user config"
pass "the console selection lives in Omarchy user config"

grep -Fq "omarchy-launch-console" "$ROOT/default/hypr/qconsole.lua" ||
  fail "the Quake console seeds itself with the launcher"
pass "the Quake console seeds itself with the launcher"
