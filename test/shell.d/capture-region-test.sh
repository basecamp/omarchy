#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""
cleanup() {
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

TMPDIR=$(mktemp -d)
stub_bin="$TMPDIR/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

case "$*" in
  "monitors -j")
    printf '%s\n' '[{"name":"focused","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"focused":true,"activeWorkspace":{"id":1}},{"name":"empty","x":1920,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"focused":false,"activeWorkspace":{"id":2}}]'
    ;;
  "clients -j")
    printf '%s\n' '[{"at":[0,26],"size":[1920,1054],"workspace":{"id":1},"hidden":false}]'
    ;;
  "cursorpos")
    printf '%s\n' '110, 10'
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/hyprctl"

cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash
[[ $* == "shell listCaptureTargets" ]] || exit 1
printf '%s\n' '[{"id":"omarchy.clock","screen":"focused","x":100,"y":32,"width":360,"height":420,"visible":true},{"id":"omarchy.network","screen":"empty","x":2020,"y":32,"width":420,"height":530,"visible":true}]'
SH
chmod +x "$stub_bin/omarchy-shell"

cat >"$stub_bin/hyprpicker" <<'SH'
#!/bin/bash
while :; do sleep 1; done
SH
chmod +x "$stub_bin/hyprpicker"

cat >"$stub_bin/slurp" <<'SH'
#!/bin/bash
cat >"$CAPTURE_CANDIDATES"
printf '%s\n' '100,32 360x420'
SH
chmod +x "$stub_bin/slurp"

CAPTURE_CANDIDATES="$TMPDIR/candidates"
selection=$(
  OMARCHY_PATH="$ROOT" \
  CAPTURE_CANDIDATES="$CAPTURE_CANDIDATES" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-capture-region" smart
)

grep -Fx '100,32 360x420' "$CAPTURE_CANDIDATES" >/dev/null \
  || fail "smart picker receives open-plugin panel geometry"
grep -Fx '2020,32 420x530' "$CAPTURE_CANDIDATES" >/dev/null \
  || fail "smart picker receives secondary-monitor open-plugin panel geometry"
grep -Fx '0,0 1920x1080' "$CAPTURE_CANDIDATES" >/dev/null \
  || fail "smart picker keeps monitor geometry"
grep -Fx '1920,0 1920x1080' "$CAPTURE_CANDIDATES" >/dev/null \
  || fail "smart picker keeps an empty secondary monitor"
grep -Fx '0,26 1920x1054' "$CAPTURE_CANDIDATES" >/dev/null \
  || fail "smart picker keeps application-window geometry"
[[ $selection == '100,32 360x420' ]] \
  || fail "smart picker captures the plugin-sized selection" "got: $selection"

pass "smart screenshot picker includes open-plugin panel geometry"
