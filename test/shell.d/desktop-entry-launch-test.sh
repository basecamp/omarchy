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

cat >"$mock_bin/omarchy-font-set" <<'SH'
#!/bin/bash
printf 'font:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

for command in omarchy-pkg-aur-add omarchy-install-emacs omazed omarchy-theme-set-vscode omarchy-install-gaming-gpu-lib32; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
exit 0
SH
done

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
printf 'launch:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >"$OMARCHY_TEST_PRESENTATION"
SH

chmod +x "$mock_bin"/*

export HOME="$test_home"
export OMARCHY_TEST_LOG="$test_tmp/launch.log"
export OMARCHY_TEST_PRESENTATION="$test_tmp/presentation"
export PATH="$mock_bin:$PATH"

wait_for_launch() {
  local expected="$1"

  for ((attempt = 0; attempt < 100; attempt++)); do
    grep -Fxq "$expected" "$OMARCHY_TEST_LOG" && return 0
    sleep 0.01
  done

  return 1
}

assert_detached_installer_launch() {
  local script="$1"
  local desktop_id="$2"

  : >"$OMARCHY_TEST_LOG"
  bash "$ROOT/bin/$script"

  wait_for_launch "launch:uwsm-app -- gtk-launch $desktop_id" ||
    fail "$script launches its desktop entry through gtk-launch in a UWSM scope"
  grep -Fqx "setsid uwsm-app -- gtk-launch $desktop_id >/dev/null 2>&1 &" "$ROOT/bin/$script" ||
    fail "$script detaches its scoped desktop-entry launch"
  pass "$script detaches its scoped desktop-entry launch"
}

assert_detached_installer_launch omarchy-install-editor-emacs emacsclient
assert_detached_installer_launch omarchy-install-editor-vscode code
assert_detached_installer_launch omarchy-install-editor-zed dev.zed.Zed
assert_detached_installer_launch omarchy-install-gaming-heroic heroic
assert_detached_installer_launch omarchy-install-gaming-steam steam

bash "$ROOT/bin/omarchy-install-and-launch" "Example App" "alpha beta" "Disk Usage"
presentation_command=$(<"$OMARCHY_TEST_PRESENTATION")

[[ $presentation_command == *'echo Installing\ Example\ App...;'* ]] ||
  fail "generic installer shell-quotes the display name" "$presentation_command"
[[ $presentation_command == *'omarchy-pkg-add alpha beta && (setsid uwsm-app -- gtk-launch Disk\ Usage >/dev/null 2>&1 &)'* ]] ||
  fail "generic installer waits for packages and detaches only the scoped launch" "$presentation_command"
pass "generic installer waits for packages and detaches only the scoped launch"

: >"$OMARCHY_TEST_LOG"
bash -c "$presentation_command"
grep -Fxq 'pkg:alpha beta' "$OMARCHY_TEST_LOG" ||
  fail "generic installer passes every package to the package helper"
wait_for_launch 'launch:uwsm-app -- gtk-launch Disk Usage' ||
  fail "generic installer preserves a desktop ID containing spaces"
pass "generic installer preserves a desktop ID containing spaces"

: >"$OMARCHY_TEST_LOG"
if OMARCHY_TEST_PKG_STATUS=1 bash -c "$presentation_command"; then
  fail "generic installer propagates package installation failure"
fi
if grep -q '^launch:' "$OMARCHY_TEST_LOG"; then
  fail "generic installer does not launch after package installation failure"
fi
pass "generic installer does not launch after package installation failure"

run_presentation() {
  bash -c "sleep() { :; }; $(<"$OMARCHY_TEST_PRESENTATION")"
}

bash "$ROOT/bin/omarchy-install-app" "LM Studio" "lmstudio-bin"
presentation_command=$(<"$OMARCHY_TEST_PRESENTATION")
[[ $presentation_command == *'echo Installing\ LM\ Studio...;'* ]] ||
  fail "install-app shell-quotes the display name" "$presentation_command"
[[ $presentation_command == *'omarchy-pkg-add lmstudio-bin'* ]] ||
  fail "install-app still passes the package list through" "$presentation_command"
pass "install-app shell-quotes the display name"

bash "$ROOT/bin/omarchy-install-app" "Example App" "alpha beta"
presentation_command=$(<"$OMARCHY_TEST_PRESENTATION")
[[ $presentation_command == 'echo Installing\ Example\ App...; omarchy-pkg-add alpha beta' ]] ||
  fail "install-app builds the presentation command with no stray argument" "$presentation_command"
: >"$OMARCHY_TEST_LOG"
run_presentation
grep -Fxq 'pkg:alpha beta' "$OMARCHY_TEST_LOG" ||
  fail "install-app passes every package to the package helper"
pass "install-app passes every package to the package helper"

bash "$ROOT/bin/omarchy-install-app" "Foo's App" "alpha"
presentation_command=$(<"$OMARCHY_TEST_PRESENTATION")
quoted_app_message="echo $(printf '%q' "Installing Foo's App...");"
[[ $presentation_command == "$quoted_app_message"* ]] ||
  fail "install-app shell-quotes an apostrophe in the display name" "$presentation_command"
: >"$OMARCHY_TEST_LOG"
run_presentation >"$test_tmp/app-apostrophe.out"
grep -Fxq 'pkg:alpha' "$OMARCHY_TEST_LOG" ||
  fail "install-app still installs when the display name has an apostrophe"
pass "install-app still installs when the display name has an apostrophe"

bash "$ROOT/bin/omarchy-install-app" "a'; echo PWNED; echo '" "alpha"
: >"$OMARCHY_TEST_LOG"
run_presentation >"$test_tmp/app-inject.out"
if grep -Fxq 'PWNED' "$test_tmp/app-inject.out"; then
  fail "install-app does not run extra commands from a quote in the display name" "$(<"$test_tmp/app-inject.out")"
fi
grep -Fxq 'pkg:alpha' "$OMARCHY_TEST_LOG" ||
  fail "install-app still installs after quoting a hostile display name"
pass "install-app does not run extra commands from a quote in the display name"

bash "$ROOT/bin/omarchy-install-font" "Cascadia Mono" "ttf-cascadia-mono-nerd" "CaskaydiaMono Nerd Font"
presentation_command=$(<"$OMARCHY_TEST_PRESENTATION")
[[ $presentation_command == *'echo Installing\ Cascadia\ Mono...;'* ]] ||
  fail "install-font shell-quotes the display name" "$presentation_command"
[[ $presentation_command == *'omarchy-font-set CaskaydiaMono\ Nerd\ Font'* ]] ||
  fail "install-font shell-quotes a font family with spaces" "$presentation_command"
: >"$OMARCHY_TEST_LOG"
run_presentation
grep -Fxq 'pkg:ttf-cascadia-mono-nerd' "$OMARCHY_TEST_LOG" ||
  fail "install-font installs the font package"
grep -Fxq 'font:CaskaydiaMono Nerd Font' "$OMARCHY_TEST_LOG" ||
  fail "install-font passes the family name through as one argument"
pass "install-font shell-quotes the display name and family"

bash "$ROOT/bin/omarchy-install-font" "Foo's App" "alpha" "Foo's Font"
: >"$OMARCHY_TEST_LOG"
run_presentation >"$test_tmp/font-apostrophe.out"
grep -Fxq 'pkg:alpha' "$OMARCHY_TEST_LOG" ||
  fail "install-font still installs when the display name has an apostrophe"
grep -Fxq "font:Foo's Font" "$OMARCHY_TEST_LOG" ||
  fail "install-font still sets the family when it has an apostrophe"
pass "install-font still installs when the name or family has an apostrophe"

bash "$ROOT/bin/omarchy-install-font" "a'; echo PWNED; echo '" "alpha" "a'; echo PWNED; echo '"
: >"$OMARCHY_TEST_LOG"
run_presentation >"$test_tmp/font-inject.out"
if grep -Fxq 'PWNED' "$test_tmp/font-inject.out"; then
  fail "install-font does not run extra commands from a quote in the name or family" "$(<"$test_tmp/font-inject.out")"
fi
grep -Fxq 'pkg:alpha' "$OMARCHY_TEST_LOG" ||
  fail "install-font still installs after quoting a hostile display name"
pass "install-font does not run extra commands from a quote in the name or family"

bash "$ROOT/bin/omarchy-install-app" "Example App" "alpha; echo PWNED"
: >"$OMARCHY_TEST_LOG"
run_presentation >"$test_tmp/app-pkg-inject.out"
if grep -Fxq 'PWNED' "$test_tmp/app-pkg-inject.out"; then
  fail "install-app does not run extra commands from a package list" "$(<"$test_tmp/app-pkg-inject.out")"
fi
grep -Fxq 'pkg:alpha; echo PWNED' "$OMARCHY_TEST_LOG" ||
  fail "install-app hands a hostile package list to the package helper as arguments" "$(<"$OMARCHY_TEST_LOG")"
pass "install-app does not run extra commands from a package list"

bash "$ROOT/bin/omarchy-install-app" "Example App" "$(printf 'alpha\nbeta')"
: >"$OMARCHY_TEST_LOG"
run_presentation
grep -Fxq 'pkg:alpha beta' "$OMARCHY_TEST_LOG" ||
  fail "install-app keeps every package when the list is newline-separated" "$(<"$OMARCHY_TEST_LOG")"
pass "install-app keeps every package when the list is newline-separated"

env SHELLOPTS=errexit bash "$ROOT/bin/omarchy-install-app" "Example App" "alpha beta" ||
  fail "install-app builds its command under an inherited errexit"
[[ $(<"$OMARCHY_TEST_PRESENTATION") == 'echo Installing\ Example\ App...; omarchy-pkg-add alpha beta' ]] ||
  fail "install-app builds the same command under an inherited errexit" "$(<"$OMARCHY_TEST_PRESENTATION")"
env SHELLOPTS=errexit bash "$ROOT/bin/omarchy-install-and-launch" "Example App" "alpha beta" "Disk Usage" ||
  fail "install-and-launch builds its command under an inherited errexit"
grep -Fq 'omarchy-pkg-add alpha beta' "$OMARCHY_TEST_PRESENTATION" ||
  fail "install-and-launch keeps its package list under an inherited errexit" "$(<"$OMARCHY_TEST_PRESENTATION")"
pass "the installers build their command under an inherited errexit"

bash "$ROOT/bin/omarchy-install-font" "Example Font" "alpha; echo PWNED" "Example Family"
: >"$OMARCHY_TEST_LOG"
run_presentation >"$test_tmp/font-pkg-inject.out"
if grep -Fxq 'PWNED' "$test_tmp/font-pkg-inject.out"; then
  fail "install-font does not run extra commands from its package" "$(<"$test_tmp/font-pkg-inject.out")"
fi
grep -Fxq 'pkg:alpha; echo PWNED' "$OMARCHY_TEST_LOG" ||
  fail "install-font hands a hostile package to the package helper as one argument" "$(<"$OMARCHY_TEST_LOG")"
pass "install-font does not run extra commands from its package"

bash "$ROOT/bin/omarchy-install-font" "Example Font" "alpha" "Example Family"
: >"$OMARCHY_TEST_LOG"
if OMARCHY_TEST_PKG_STATUS=1 run_presentation; then
  fail "install-font propagates package installation failure"
fi
if grep -q '^font:' "$OMARCHY_TEST_LOG"; then
  fail "install-font does not set the family after package installation failure" "$(<"$OMARCHY_TEST_LOG")"
fi
pass "install-font does not set the family after package installation failure"

bash "$ROOT/bin/omarchy-install-and-launch" "Example App" "alpha; echo PWNED" "Disk Usage"
: >"$OMARCHY_TEST_LOG"
run_presentation >"$test_tmp/launch-pkg-inject.out"
if grep -Fxq 'PWNED' "$test_tmp/launch-pkg-inject.out"; then
  fail "install-and-launch does not run extra commands from a package list" "$(<"$test_tmp/launch-pkg-inject.out")"
fi
grep -Fxq 'pkg:alpha; echo PWNED' "$OMARCHY_TEST_LOG" ||
  fail "install-and-launch hands a hostile package list to the package helper as arguments" "$(<"$OMARCHY_TEST_LOG")"
pass "install-and-launch does not run extra commands from a package list"
