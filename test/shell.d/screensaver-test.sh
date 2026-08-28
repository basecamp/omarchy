#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command script
require_command timeout

test_tmp=$(mktemp -d)
mock_bin="$test_tmp/bin"
call_log="$test_tmp/ttfx-calls"
pid_file="$test_tmp/ttfx-pid"
mkdir -p "$mock_bin" "$test_tmp/home/.config/omarchy/branding"
printf 'Omarchy\n' >"$test_tmp/home/.config/omarchy/branding/screensaver.txt"

cleanup() {
  if [[ -s $pid_file ]]; then
    kill "$(<"$pid_file")" 2>/dev/null || true
  fi
  rm -rf "$test_tmp"
}
trap cleanup EXIT

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
if [[ $* == "activewindow -j" ]]; then
  printf '{"class":"org.omarchy.screensaver"}\n'
fi
SH

cat >"$mock_bin/ttfx" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$CALL_LOG"
printf '%s\n' "$$" >"$TTFX_PID_FILE"
kill -HUP "$PPID"
rm -f "$TTFX_PID_FILE"
SH

cat >"$mock_bin/pkill" <<'SH'
#!/bin/bash
if [[ $* == *"ttfx"* && -s $TTFX_PID_FILE ]]; then
  kill "$(<"$TTFX_PID_FILE")" 2>/dev/null || true
fi
SH

chmod +x "$mock_bin/hyprctl" "$mock_bin/ttfx" "$mock_bin/pkill"

run_screensaver() {
  local frame_rate=$1
  HOME="$test_tmp/home" \
    PATH="$mock_bin:$PATH" \
    CALL_LOG="$call_log" \
    TTFX_PID_FILE="$pid_file" \
    OMARCHY_SCREENSAVER_FRAME_RATE="$frame_rate" \
    timeout 2s script -qefc "$ROOT/bin/omarchy-screensaver" /dev/null >/dev/null 2>&1 || true
}

run_screensaver 20
grep -q -- '--frame-rate 20' "$call_log" || fail "screensaver forwards configured frame rate"

: >"$call_log"
HOME="$test_tmp/home" \
  PATH="$mock_bin:$PATH" \
  CALL_LOG="$call_log" \
  TTFX_PID_FILE="$pid_file" \
  timeout 2s script -qefc "$ROOT/bin/omarchy-screensaver" /dev/null >/dev/null 2>&1 || true
grep -q -- '--frame-rate 120' "$call_log" || fail "screensaver keeps the 120 FPS default"

for invalid in 0 241 twenty; do
  set +e
  OMARCHY_SCREENSAVER_FRAME_RATE="$invalid" timeout 2s "$ROOT/bin/omarchy-screensaver" >/dev/null 2>&1
  status=$?
  set -e

  (( status != 124 )) || fail "screensaver rejects invalid frame rate without hanging" "timed out: $invalid"
  (( status == 1 )) || fail "screensaver rejects invalid frame rate" "value: $invalid, exit status: $status"
done

pass "screensaver validates and forwards its frame rate"
