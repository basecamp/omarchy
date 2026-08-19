#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir" "$RECORDING_FILE"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

RECORDING_FILE="/tmp/omarchy-screenrecord-filename"
GSR_LOG="$tmp_dir/gsr.log"
NOTIF_LOG="$tmp_dir/notif.log"
rm -f "$RECORDING_FILE"
: >"$GSR_LOG"
: >"$NOTIF_LOG"

# gpu-screen-recorder stub: the kms launch (-w <monitor>) exits without writing
# the file (the "failed to find monitor by name" failure on a dGPU-driven
# external monitor); the portal retry (-w portal) touches the output file and
# stays alive so the script's wait loop sees it succeed. OMARCHY_TEST_PORTAL_FAILS
# flips the portal branch to fail too, for the no-retry case.
cat >"$stub_bin/gpu-screen-recorder" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_GSR_LOG"
w=""; out=""; prev=""
for a in "$@"; do
  [[ $prev == -w ]] && w="$a"
  [[ $prev == -o ]] && out="$a"
  prev="$a"
done
if [[ $w == portal && ${OMARCHY_TEST_PORTAL_FAILS:-false} != true ]]; then
  [[ -n $out ]] && touch -- "$out"
  sleep 5
else
  exit 1
fi
SH

cat >"$stub_bin/pgrep" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$stub_bin/pkill" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >>"$OMARCHY_TEST_NOTIF_LOG"
SH

cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/omarchy-hyprland-monitor-focused" <<'SH'
#!/bin/bash
echo "eDP-2"
SH

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
case "$1" in
monitors) printf '[{"focused":true,"width":1920,"height":1080}]' ;;
*) printf '{}' ;;
esac
SH

chmod +x "$stub_bin"/*

mkdir -p "$tmp_dir/videos"
export PATH="$stub_bin:$ROOT/bin:$PATH"
export HOME="$tmp_dir/home"
mkdir -p "$HOME"
export XDG_VIDEOS_DIR="$tmp_dir/videos"
export OMARCHY_TEST_GSR_LOG="$GSR_LOG"
export OMARCHY_TEST_NOTIF_LOG="$NOTIF_LOG"

# kms fails -> portal retry succeeds.
"$ROOT/bin/omarchy-capture-screenrecording" --fullscreen --resolution=0x0
filename=$(cat "$RECORDING_FILE")
[[ -n $filename ]] || fail "portal fallback wrote the recording file" "$(cat "$RECORDING_FILE")"
[[ -f $filename ]] || fail "portal fallback created the recording file on disk"

# Two gsr invocations: first the kms monitor target, then the portal retry.
calls=$(grep -c . "$GSR_LOG") || true
(( calls == 2 )) || fail "kms failure retried exactly once via portal" "got $calls calls:$(cat "$GSR_LOG")"
grep -q -- '-w eDP-2' "$GSR_LOG" || fail "first attempt targets the focused monitor via kms" "$(cat "$GSR_LOG")"
grep -q -- '-w portal' "$GSR_LOG" || fail "retry targets the portal backend" "$(cat "$GSR_LOG")"
grep -Fx -- 'Retrying screen recording via the portal backend' "$NOTIF_LOG" >/dev/null || \
  fail "fallback notifies the user" "$(cat "$NOTIF_LOG")"
pass "kms failure falls back to the portal backend and records"

# When the user already opted into the portal and it also fails, do not retry again.
rm -f "$RECORDING_FILE" "$filename" 2>/dev/null
: >"$GSR_LOG"
OMARCHY_TEST_PORTAL_FAILS=true OMARCHY_SCREENRECORD_USE_PORTAL=true \
  "$ROOT/bin/omarchy-capture-screenrecording" --resolution=0x0 || true
calls=$(grep -c . "$GSR_LOG") || true
(( calls == 1 )) || fail "portal failure is not retried again" "got $calls calls:$(cat "$GSR_LOG")"
grep -q -- '-w portal' "$GSR_LOG" || fail "the single attempt used portal" "$(cat "$GSR_LOG")"
[[ ! -f $RECORDING_FILE ]] || fail "no recording file when both backends fail"
pass "portal failure is not retried again"
