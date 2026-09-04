#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

picker_bin="$work/picker-bin"
client_bin="$work/client-bin"
mkdir -p "$picker_bin" "$client_bin" "$work/shots"

cat > "$picker_bin/slurp" <<'SH'
#!/bin/bash
printf '1,2 30x40\n'
SH

cat > "$picker_bin/hyprpicker" <<'SH'
#!/bin/bash
printf 'hyprpicker\n' >> "$CAPTURE_CALLS"
exec sleep 30
SH

chmod +x "$picker_bin/slurp" "$picker_bin/hyprpicker"

CAPTURE_CALLS="$work/picker.calls" PATH="$picker_bin:$PATH" \
  "$ROOT/bin/omarchy-capture-region" region > "$work/default.out"
grep -qx '1,2 30x40' "$work/default.out" || fail "default capture returns the selection"
grep -qx 'hyprpicker' "$work/picker.calls" || fail "default capture starts the frozen overlay"

: > "$work/picker.calls"
CAPTURE_CALLS="$work/picker.calls" PATH="$picker_bin:$PATH" \
  "$ROOT/bin/omarchy-capture-region" region --no-freeze > "$work/flag.out"
grep -qx '1,2 30x40' "$work/flag.out" || fail "no-freeze capture returns the selection"
[[ ! -s $work/picker.calls ]] || fail "--no-freeze skips the frozen overlay"

CAPTURE_CALLS="$work/picker.calls" OMARCHY_CAPTURE_FREEZE=false PATH="$picker_bin:$PATH" \
  "$ROOT/bin/omarchy-capture-region" region > "$work/env.out"
grep -qx '1,2 30x40' "$work/env.out" || fail "environment-safe capture returns the selection"
[[ ! -s $work/picker.calls ]] || fail "OMARCHY_CAPTURE_FREEZE=false skips the frozen overlay"

CAPTURE_CALLS="$work/picker.calls" PATH="$picker_bin:$PATH" \
  "$ROOT/bin/omarchy-capture-region" region --keep-freeze --no-freeze > "$work/protocol.out"
[[ $(sed -n '1p' "$work/protocol.out") == "" ]] || fail "safe keep-freeze protocol emits an empty PID"
[[ $(sed -n '2p' "$work/protocol.out") == "1,2 30x40" ]] || fail "safe keep-freeze protocol preserves the selection"

cat > "$client_bin/omarchy-capture-region" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$CAPTURE_CALLS"
printf '\n1,2 30x40\n'
SH

cat > "$client_bin/hyprctl" <<'SH'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >> "$CAPTURE_CALLS"
exit 1
SH

cat > "$client_bin/pkill" <<'SH'
#!/bin/bash
exit 1
SH

cat > "$client_bin/grim" <<'SH'
#!/bin/bash
printf 'image'
SH

cat > "$client_bin/tesseract" <<'SH'
#!/bin/bash
cat >/dev/null
printf 'captured text\n'
SH

cat > "$client_bin/zbarimg" <<'SH'
#!/bin/bash
cat >/dev/null
printf 'https://example.test\n'
SH

cat > "$client_bin/wl-copy" <<'SH'
#!/bin/bash
cat >/dev/null
SH

cat > "$client_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$client_bin"/*

: > "$work/client.calls"
CAPTURE_CALLS="$work/client.calls" OMARCHY_SCREENSHOT_DIR="$work/shots" PATH="$client_bin:$PATH" \
  "$ROOT/bin/omarchy-capture-screenshot" region save --no-freeze >/dev/null
grep -qx 'region --keep-freeze --no-freeze' "$work/client.calls" || fail "screenshot forwards --no-freeze"
! grep -q '^hyprctl ' "$work/client.calls" || fail "safe screenshot does not change cursor rendering"

: > "$work/client.calls"
CAPTURE_CALLS="$work/client.calls" PATH="$client_bin:$PATH" \
  "$ROOT/bin/omarchy-capture-text" --no-freeze
grep -qx 'region --keep-freeze --no-freeze' "$work/client.calls" || fail "OCR forwards --no-freeze"

: > "$work/client.calls"
CAPTURE_CALLS="$work/client.calls" PATH="$client_bin:$PATH" \
  "$ROOT/bin/omarchy-capture-qr" --no-freeze
grep -qx 'region --keep-freeze --no-freeze' "$work/client.calls" || fail "QR capture forwards --no-freeze"

pass "capture commands provide a live-screen fallback without changing defaults"
