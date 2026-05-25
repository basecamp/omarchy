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
  pass "no Wayland compositor; skipping shell runtime smoke test"
  exit 0
fi

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping shell runtime smoke test"
  exit 0
fi

require_command jq

TMPDIR=$(mktemp -d)
test_root="$TMPDIR/omarchy"
test_home="$TMPDIR/home"
stub_bin="$TMPDIR/bin"
log="$TMPDIR/quickshell.log"
mkdir -p "$test_root" "$test_home" "$stub_bin"
cp -a "$ROOT/shell" "$test_root/shell"
ln -s "$ROOT/config" "$test_root/config"
ln -s "$ROOT/bin" "$test_root/bin"

cat >"$stub_bin/omarchy-update-available" <<'SH'
#!/bin/bash
echo "Omarchy update available (test)"
exit 0
SH
chmod +x "$stub_bin/omarchy-update-available"

OMARCHY_PATH="$test_root" \
HOME="$test_home" \
PATH="$stub_bin:$ROOT/bin:$PATH" \
  quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  if OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" -q shell ping >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,200p' "$log" >&2
    fail "test shell exited before IPC became available"
  fi
  sleep 0.1
done

OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" -q omarchy.system-update refresh >/dev/null 2>&1 || true
sleep 0.8

geometry=$(OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" shell debugBarGeometry)
if [[ -z $geometry ]]; then
  sed -n '1,200p' "$log" >&2
  fail "debug bar geometry returned output"
fi

jq -e '
  map(select(.section == "center" and .visible == true)) as $center |
  ($center | map(select(.id == "omarchy.weather" and .visible == true)) | length) >= 1 and
  ($center | map(select(.id == "omarchy.system-update" and .visible == true and .width > 0)) | length) >= 1 and
  ($center | map(select(.id == "omarchy.indicators" and .visible == true)) | length) >= 1 and
  (
    ($center | map(select(.id == "omarchy.weather")) | first | .x) <
    ($center | map(select(.id == "omarchy.system-update")) | first | .x)
  ) and
  (
    ($center | map(select(.id == "omarchy.system-update")) | first | .x) <
    ($center | map(select(.id == "omarchy.indicators")) | first | .x)
  )
' <<<"$geometry" >/dev/null || {
  printf 'Geometry:\n%s\n' "$geometry" | jq . >&2
  sed -n '1,200p' "$log" >&2
  fail "runtime geometry places visible update between weather and indicators"
}

pass "runtime geometry places visible update between weather and indicators"
