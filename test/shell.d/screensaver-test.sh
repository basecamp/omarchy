#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "activewindow" && $2 == "-j" ]]; then
  printf '%s\n' "${OMARCHY_TEST_ACTIVEWINDOW_JSON-}"
  exit 0
fi

exit 1
SH

# --check-focus must not start the screensaver; if the hook is missing these
# would be invoked and the test would fail instead of hanging in ttfx.
cat >"$stub_bin/ttfx" <<'SH'
#!/bin/bash
printf 'ttfx must not run during --check-focus\n' >&2
exit 99
SH

chmod +x "$stub_bin/hyprctl" "$stub_bin/ttfx"

check_focus() {
  PATH="$stub_bin:$PATH" OMARCHY_TEST_ACTIVEWINDOW_JSON="$1" \
    "$ROOT/bin/omarchy-screensaver" --check-focus
}

assert_stays() {
  local json="$1"
  local description="$2"

  if check_focus "$json"; then
    pass "$description"
  else
    fail "$description"
  fi
}

assert_dismisses() {
  local json="$1"
  local description="$2"

  if check_focus "$json"; then
    fail "$description"
  else
    pass "$description"
  fi
}

assert_stays '{"address":"0xaaa","class":"org.omarchy.screensaver"}' \
  "screensaver stays when this screensaver window is focused"

assert_stays '{"address":"0xbbb","class":"org.omarchy.screensaver","title":"DP-3"}' \
  "screensaver stays when another screensaver window is focused"

assert_dismisses '{"class":"kitty"}' \
  "screensaver dismisses when kitty is focused"

assert_dismisses '{"class":"firefox"}' \
  "screensaver dismisses when firefox is focused"

assert_stays '{}' \
  "screensaver stays when activewindow has no class"

assert_stays '{"address":"0xccc","class":null}' \
  "screensaver stays when activewindow class is null"

assert_stays 'null' \
  "screensaver stays when activewindow is null"

assert_stays '' \
  "screensaver stays when activewindow is empty during a monitor switch"

if rg -F -q "pkill -f '[o]rg.omarchy.screensaver'" "$ROOT/bin/omarchy-screensaver"; then
  pass "real dismiss still kills all screensaver clients"
else
  fail "real dismiss still kills all screensaver clients"
fi
