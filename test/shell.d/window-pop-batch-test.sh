#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

log="$tmpdir/hyprctl.log"
cat >"$tmpdir/hyprctl" <<'BASH'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
if [[ $1 == "activewindow" ]]; then
  printf '{"pinned":%s,"address":"0x1"}\n' "${HYPR_PINNED:-false}"
  exit 0
fi
if [[ $1 == "--batch" || $1 == "dispatch" ]]; then
  exit 0
fi
exit 1
BASH
chmod +x "$tmpdir/hyprctl"

PATH="$tmpdir:$PATH" HYPRCTL_LOG="$log" HYPR_PINNED=false \
  "$ROOT/bin/omarchy-hyprland-window-pop" >/dev/null

grep -c '^--batch ' "$log" | grep -qx 1 ||
  fail "popping a window sends one hyprctl --batch" "$(cat "$log")"
! grep -q '^dispatch ' "$log" ||
  fail "popping a window does not send per-action dispatch processes" "$(cat "$log")"
grep -Fq 'hl.dsp.window.float' "$log" || fail "the batch still floats the window" "$(cat "$log")"
grep -Fq 'hl.dsp.window.pin' "$log" || fail "the batch still pins the window" "$(cat "$log")"
grep -Fq 'hl.dsp.window.tag({ window = "address:0x1", tag = "+pop" })' "$log" ||
  fail "the batch still tags the popped window" "$(cat "$log")"
pass "popping a window is one hyprctl batch"

: >"$log"
PATH="$tmpdir:$PATH" HYPRCTL_LOG="$log" HYPR_PINNED=true \
  "$ROOT/bin/omarchy-hyprland-window-pop" >/dev/null

grep -c '^--batch ' "$log" | grep -qx 1 ||
  fail "unpopping a window sends one hyprctl --batch" "$(cat "$log")"
grep -Fq 'tag = "-pop"' "$log" || fail "the unpop batch removes the pop tag" "$(cat "$log")"
pass "unpopping a window is one hyprctl batch"

: >"$log"
cat >"$tmpdir/hyprctl" <<'BASH'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
if [[ $1 == "activewindow" ]]; then
  printf '{"pinned":false,"address":"0x1"}\n'
  exit 0
fi
if [[ $1 == "--batch" ]]; then
  exit 1
fi
if [[ $1 == "dispatch" ]]; then
  exit 0
fi
exit 1
BASH
chmod +x "$tmpdir/hyprctl"

PATH="$tmpdir:$PATH" HYPRCTL_LOG="$log" \
  "$ROOT/bin/omarchy-hyprland-window-pop" >/dev/null

grep -q '^--batch ' "$log" || fail "a failed batch is still attempted" "$(cat "$log")"
grep -q '^dispatch ' "$log" || fail "a failed batch falls back to sequential dispatch" "$(cat "$log")"
pass "a compositor without --batch still pops via sequential dispatch"
