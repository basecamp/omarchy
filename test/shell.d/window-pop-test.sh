#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_bin="$tmpdir/bin"
log="$tmpdir/hyprctl.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
printf '<%s>' "$@" >>"$HYPRCTL_LOG"
printf '\n' >>"$HYPRCTL_LOG"

if [[ $1 == "activewindow" ]]; then
  printf '{"pinned": %s, "address": "0xabc"}\n' "${WINDOW_PINNED:-false}"
elif [[ $1 == "--batch" && ${BATCH_FAIL:-0} == "1" ]]; then
  exit 1
fi
SH
chmod +x "$stub_bin/hyprctl"

run_pop() {
  HYPRCTL_LOG="$log" PATH="$stub_bin:$PATH" \
    bash "$ROOT/bin/omarchy-hyprland-window-pop" "$@"
}

run_pop
(( $(wc -l <"$log") == 2 )) ||
  fail "window pop uses one compositor batch" "$(cat "$log")"
grep -q '<--batch><dispatch hl.dsp.window.float.*hl.dsp.window.resize.*hl.dsp.window.center.*hl.dsp.window.pin.*hl.dsp.window.alter_zorder.*hl.dsp.window.tag' "$log" ||
  fail "window pop batches its six actions in order" "$(cat "$log")"
pass "window pop uses one compositor batch"

: >"$log"
BATCH_FAIL=1 run_pop
(( $(wc -l <"$log") == 8 )) ||
  fail "window pop falls back to six sequential dispatches" "$(cat "$log")"
(( $(grep -c '^<dispatch><hl.dsp.window' "$log") == 6 )) ||
  fail "window pop fallback keeps the Lua dispatch path" "$(cat "$log")"
pass "window pop falls back to sequential dispatches"

: >"$log"
WINDOW_PINNED=true run_pop
(( $(wc -l <"$log") == 2 )) ||
  fail "window unpop uses one compositor batch" "$(cat "$log")"
grep -q '<--batch><dispatch hl.dsp.window.pin.*hl.dsp.window.float.*hl.dsp.window.tag' "$log" ||
  fail "window unpop batches its three actions in order" "$(cat "$log")"
pass "window unpop uses one compositor batch"
