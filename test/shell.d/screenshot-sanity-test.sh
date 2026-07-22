#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""
QS_PID=""

cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  pass "no Wayland compositor; skipping screenshot sanity test"
  exit 0
fi

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping screenshot sanity test"
  exit 0
fi

if pgrep -x slurp >/dev/null 2>&1; then
  pass "slurp is already running; skipping screenshot sanity test"
  exit 0
fi

require_command hyprctl
require_command grim
require_command jq
require_command python3

shell_ipc() {
  OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" "$@"
}

shell_ipc_quiet() {
  OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" -q "$@"
}

fail_with_log() {
  local description="$1"
  sed -n '1,220p' "$log" >&2
  [[ -f $screenshot_err ]] && sed -n '1,120p' "$screenshot_err" >&2
  fail "$description"
}

TMPDIR=$(mktemp -d)
test_root="$TMPDIR/omarchy"
test_home="$TMPDIR/home"
stub_bin="$TMPDIR/bin"
screenshot_dir="$TMPDIR/screenshots"
log="$TMPDIR/quickshell.log"
screenshot_err="$TMPDIR/screenshot.err"
mkdir -p "$test_root" "$test_home" "$stub_bin" "$screenshot_dir"
cp -a "$ROOT/shell" "$test_root/shell"
ln -s "$ROOT/config" "$test_root/config"
ln -s "$ROOT/bin" "$test_root/bin"

cat >"$stub_bin/omarchy-update-available" <<'SH'
#!/bin/bash
echo "Omarchy update available (test)"
exit 0
SH
chmod +x "$stub_bin/omarchy-update-available"

cat >"$stub_bin/curl" <<'SH'
#!/bin/bash

case "${*: -1}" in
  *'?format=j1')
    printf '{"current_condition":[{"weatherCode":"113","temp_F":"72"}]}\n'
    ;;
  *'?format=%l')
    printf 'Test City, Test Region\n'
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/curl"

OMARCHY_PATH="$test_root" \
HOME="$test_home" \
PATH="$stub_bin:$ROOT/bin:$PATH" \
  quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  if shell_ipc_quiet shell ping >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail_with_log "screenshot test shell exited before IPC became available"
  fi
  sleep 0.1
done

shell_ipc_quiet omarchy.system-update refresh >/dev/null 2>&1 || true
sleep 0.8

geometry=$(shell_ipc shell debugBarGeometry)
jq -e '
  any(.[]; .id == "omarchy.menu" and .visible == true and .width > 0 and .height > 0) and
  any(.[]; .id == "omarchy.clock" and .visible == true and .width > 0 and .height > 0)
' <<<"$geometry" >/dev/null || {
  printf 'Geometry:\n' >&2
  jq . <<<"$geometry" >&2
  fail_with_log "screenshot test shell rendered visible bar widgets"
}

screenshot=$(
  OMARCHY_PATH="$test_root" \
  OMARCHY_SCREENSHOT_DIR="$screenshot_dir" \
  HOME="$test_home" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy" capture screenshot fullscreen save 2>"$screenshot_err" | tail -n 1
)

[[ -n $screenshot && -f $screenshot ]] || fail_with_log "fullscreen screenshot was captured"

SCREENSHOT="$screenshot" GEOMETRY="$geometry" python3 <<'PY'
import json
import os
import struct
import sys
import zlib

path = os.environ["SCREENSHOT"]
geometry = json.loads(os.environ["GEOMETRY"])

with open(path, "rb") as fh:
  data = fh.read()

if data[:8] != b"\x89PNG\r\n\x1a\n":
  print("screenshot is not a PNG", file=sys.stderr)
  sys.exit(1)

offset = 8
width = height = bit_depth = color_type = None
idat = bytearray()
while offset < len(data):
  length = struct.unpack(">I", data[offset:offset + 4])[0]
  kind = data[offset + 4:offset + 8]
  payload = data[offset + 8:offset + 8 + length]
  offset += length + 12
  if kind == b"IHDR":
    width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
    if bit_depth != 8 or compression != 0 or filtering != 0 or interlace != 0:
      print("unsupported PNG format", file=sys.stderr)
      sys.exit(1)
  elif kind == b"IDAT":
    idat.extend(payload)
  elif kind == b"IEND":
    break

if not width or not height:
  print("missing PNG dimensions", file=sys.stderr)
  sys.exit(1)

channels = {0: 1, 2: 3, 6: 4}.get(color_type)
if channels is None:
  print(f"unsupported PNG color type: {color_type}", file=sys.stderr)
  sys.exit(1)

raw = zlib.decompress(bytes(idat))
stride = width * channels
rows = []
pos = 0
prev = [0] * stride

def paeth(a, b, c):
  p = a + b - c
  pa = abs(p - a)
  pb = abs(p - b)
  pc = abs(p - c)
  if pa <= pb and pa <= pc:
    return a
  if pb <= pc:
    return b
  return c

for _ in range(height):
  filter_type = raw[pos]
  pos += 1
  scan = list(raw[pos:pos + stride])
  pos += stride
  out = [0] * stride
  for i, value in enumerate(scan):
    left = out[i - channels] if i >= channels else 0
    up = prev[i]
    up_left = prev[i - channels] if i >= channels else 0
    if filter_type == 0:
      out[i] = value
    elif filter_type == 1:
      out[i] = (value + left) & 255
    elif filter_type == 2:
      out[i] = (value + up) & 255
    elif filter_type == 3:
      out[i] = (value + ((left + up) // 2)) & 255
    elif filter_type == 4:
      out[i] = (value + paeth(left, up, up_left)) & 255
    else:
      print(f"unsupported PNG filter: {filter_type}", file=sys.stderr)
      sys.exit(1)
  rows.append(out)
  prev = out

visible_heights = [int(row.get("height", 0)) for row in geometry if row.get("visible") and row.get("height", 0) > 0]
bar_height = max(24, min(80, (max(visible_heights) if visible_heights else 26) + 8))
bar_height = min(bar_height, height)

colors = set()
non_black = 0
sample_step_x = max(1, width // 320)
sample_step_y = max(1, bar_height // 12)

for y in range(0, bar_height, sample_step_y):
  row = rows[y]
  for x in range(0, width, sample_step_x):
    i = x * channels
    if color_type == 0:
      rgb = (row[i], row[i], row[i])
    else:
      rgb = tuple(row[i:i + 3])
    colors.add(rgb)
    if max(rgb) > 8:
      non_black += 1

if len(colors) < 3 or non_black == 0:
  print(f"top bar band looked blank: colors={len(colors)} non_black={non_black} size={width}x{height}", file=sys.stderr)
  sys.exit(1)
PY

pass "fullscreen screenshot shows a nonblank bar band"
