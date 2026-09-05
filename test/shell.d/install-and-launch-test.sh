#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin" "$test_home"

cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
exit "${OMARCHY_TEST_PKG_STATUS:-0}"
SH

cat >"$mock_bin/omarchy-show-logo" <<'SH'
#!/bin/bash
printf 'logo\n' >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/omarchy-show-done" <<'SH'
#!/bin/bash
printf 'done\n' >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$mock_bin/uwsm-app" <<'SH'
#!/bin/bash
if [[ ${1-} == -- ]]; then
  shift
fi
exec "$@"
SH

cat >"$mock_bin/xdg-terminal-exec" <<'SH'
#!/bin/bash
while (($# > 0)); do
  if [[ $1 == -e ]]; then
    shift
    if [[ ${1-} == bash && ${2-} == -c ]]; then
      printf '%s' "$3" >"$OMARCHY_TEST_SCRIPT"
    fi
    exec "$@"
  fi
  shift
done
exit 1
SH

cat >"$mock_bin/gtk-launch" <<'SH'
#!/bin/bash
printf 'launch:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<SH
#!/bin/bash
printf '%s\n' "\$@" >"\$OMARCHY_TEST_ARGS"
exec "$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "\$@"
SH

chmod +x "$mock_bin"/*

export HOME="$test_home"
export OMARCHY_TEST_LOG="$test_tmp/sequence.log"
export OMARCHY_TEST_ARGS="$test_tmp/launcher.args"
export OMARCHY_TEST_SCRIPT="$test_tmp/presentation.script"
export PATH="$mock_bin:$ROOT/bin:$PATH"

wait_for_log() {
  local expected="$1"

  for ((attempt = 0; attempt < 100; attempt++)); do
    grep -Fxq "$expected" "$OMARCHY_TEST_LOG" && return 0
    sleep 0.01
  done

  return 1
}

assert_log() {
  local expected="$1"
  local description="$2"
  local actual

  actual=$(<"$OMARCHY_TEST_LOG")
  [[ $actual == "$expected" ]] || fail "$description" "$actual"
  pass "$description"
}

run_install() {
  : >"$OMARCHY_TEST_LOG"
  : >"$OMARCHY_TEST_ARGS"
  : >"$OMARCHY_TEST_SCRIPT"
  bash "$ROOT/bin/omarchy-install-and-launch" "$@" >/dev/null
}

run_presentation() {
  : >"$OMARCHY_TEST_LOG"
  : >"$OMARCHY_TEST_SCRIPT"
  bash "$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "$@" >/dev/null
}

run_install "Example App" "alpha beta" "Disk Usage"

mapfile -t launcher_args <"$OMARCHY_TEST_ARGS"
[[ ${launcher_args[0]} == "--after-done" ]] ||
  fail "install-and-launch hands the wrapper a post-Done command" "$(<"$OMARCHY_TEST_ARGS")"
after_done=${launcher_args[1]}
wrapped_cmd=${launcher_args[2]}

[[ $wrapped_cmd == *'echo Installing\ Example\ App...;'* ]] ||
  fail "install-and-launch shell-quotes the display name" "$wrapped_cmd"
[[ $wrapped_cmd == *'omarchy-pkg-add alpha beta'* ]] ||
  fail "install-and-launch installs packages in the presentation command" "$wrapped_cmd"
[[ $wrapped_cmd != *gtk-launch* && $wrapped_cmd != *uwsm-app* ]] ||
  fail "install-and-launch does not background gtk-launch before Done" "$wrapped_cmd"
[[ $after_done == *'uwsm-app -- gtk-launch Disk\ Usage'* ]] ||
  fail "install-and-launch launches through uwsm-app after Done" "$after_done"
[[ $after_done != *'& '* && $after_done != *' &' ]] ||
  fail "install-and-launch does not background gtk-launch" "$after_done"
pass "install-and-launch sequences gtk-launch after Done, not before it"

script=$(<"$OMARCHY_TEST_SCRIPT")
[[ $script == *omarchy-show-done* ]] || fail "presentation script still prompts Done" "$script"
[[ $script == *gtk-launch* ]] || fail "presentation script still launches the app" "$script"
done_hits=$(grep -o 'omarchy-show-done' <<<"$script" | wc -l)
(( done_hits == 1 )) || fail "presentation script prompts Done once" "$script"
done_at=${script%%omarchy-show-done*}
launch_at=${script%%gtk-launch*}
(( ${#done_at} < ${#launch_at} )) ||
  fail "presentation script runs gtk-launch after the Done prompt" "$script"
pass "presentation script runs gtk-launch after a single Done prompt"

wait_for_log 'launch:Disk Usage' ||
  fail "install-and-launch preserves a desktop ID containing spaces" "$(<"$OMARCHY_TEST_LOG")"
assert_log $'logo\npkg:alpha beta\ndone\nlaunch:Disk Usage' "runtime order is pkg-add, Done, then gtk-launch"

OMARCHY_TEST_PKG_STATUS=1 run_install "Example App" "alpha beta" "Disk Usage"
assert_log $'logo\npkg:alpha beta\ndone' "a failed install still shows Done and does not launch"

OMARCHY_TEST_PKG_STATUS=130 run_install "Example App" "alpha beta" "Disk Usage"
assert_log $'logo\npkg:alpha beta' "Ctrl-C skips Done and does not launch"

unset OMARCHY_TEST_PKG_STATUS
run_presentation 'omarchy-pkg-add foo'
assert_log $'logo\npkg:foo\ndone' "a plain presentation caller still gets one Done prompt"
script=$(<"$OMARCHY_TEST_SCRIPT")
[[ $script != *gtk-launch* ]] ||
  fail "a plain presentation caller is unchanged" "$script"
pass "a plain presentation caller does not launch an app"

OMARCHY_TEST_PKG_STATUS=130 run_presentation 'omarchy-pkg-add foo'
assert_log $'logo\npkg:foo' "Ctrl-C still skips Done for other callers"
