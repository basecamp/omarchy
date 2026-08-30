#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# Capture the script string the floating-terminal helper would run.
cat >"$stub_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_INSTALL_QUOTE_CAPTURE"
SH
chmod +x "$stub_bin/omarchy-launch-floating-terminal-with-presentation"

export PATH="$stub_bin:$PATH"
export OMARCHY_INSTALL_QUOTE_CAPTURE="$test_tmp/capture"

: >"$OMARCHY_INSTALL_QUOTE_CAPTURE"
bash "$ROOT/bin/omarchy-install-font" 'Cascadia' 'ttf-good; touch INJECTED' 'Family'
captured=$(<"$OMARCHY_INSTALL_QUOTE_CAPTURE")
[[ $captured == *'ttf-good\;\ touch\ INJECTED'* || $captured == *"ttf-good; touch INJECTED"* ]] || true
# %q will escape the semicolon and space so it is one word for bash -c
[[ $captured == *omarchy-pkg-add* ]] || fail "font install still calls pkg-add" "$captured"
# The dangerous form is an unquoted semicolon between pkg-add and touch.
if [[ $captured =~ omarchy-pkg-add\ ttf-good\;\ touch ]]; then
  fail "font package argument was not shell-quoted" "$captured"
fi
# Accept bash %q form (backslashes) — must not contain bare `; touch`
if [[ $captured == *'; touch INJECTED'* && $captured != *'\;'* && $captured != *"';"* ]]; then
  fail "font package left a bare shell metacharacter sequence" "$captured"
fi
# Stronger: the capture must include a quoted/escaped package token, not raw
case $captured in
  *'omarchy-pkg-add ttf-good; touch'*) fail "font package was interpolated raw" "$captured" ;;
esac
pass "omarchy-install-font shell-quotes the package name"

: >"$OMARCHY_INSTALL_QUOTE_CAPTURE"
bash "$ROOT/bin/omarchy-install-app" 'App' 'pkg$(id)'
captured=$(<"$OMARCHY_INSTALL_QUOTE_CAPTURE")
case $captured in
  *'omarchy-pkg-add pkg$(id)'*) fail "app packages were interpolated raw" "$captured" ;;
esac
pass "omarchy-install-app shell-quotes the package list"

: >"$OMARCHY_INSTALL_QUOTE_CAPTURE"
bash "$ROOT/bin/omarchy-install-and-launch" 'App' 'pkg; id' 'desktop'
captured=$(<"$OMARCHY_INSTALL_QUOTE_CAPTURE")
case $captured in
  *'omarchy-pkg-add pkg; id'*) fail "and-launch packages were interpolated raw" "$captured" ;;
esac
pass "omarchy-install-and-launch shell-quotes the package list"
