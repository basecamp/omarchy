#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"
DISPATCH_LOG="$tmp_dir/dispatch.log"
export DISPATCH_LOG

# hyprctl stub: `activewindow -j` replays the window state the test sets via
# WINDOW_JSON; every dispatch lands in DISPATCH_LOG so assertions read the
# exact command sequence the pop script produced.
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
if [[ $1 == "activewindow" ]]; then
  printf '%s' "$WINDOW_JSON"
  exit 0
fi
printf '%s\n' "$*" >>"$DISPATCH_LOG"
exit 0
SH
chmod +x "$stub_bin/hyprctl"

run_pop() {
  : >"$DISPATCH_LOG"
  WINDOW_JSON="$1" PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-hyprland-window-pop" "${@:2}"
}

# A tiled window gets the full pop: float, resize, center, pin, raise, tag.
run_pop '{"address":"0x1","pinned":false,"floating":false}'
grep -Fq 'action = "toggle"' "$DISPATCH_LOG" ||
  fail "popping a tiled window floats it" "$(cat "$DISPATCH_LOG")"
grep -Fq 'window.resize' "$DISPATCH_LOG" ||
  fail "popping a tiled window sizes it" "$(cat "$DISPATCH_LOG")"
if grep -cF 'window.pin' "$DISPATCH_LOG" | grep -qv '^1$'; then
  fail "popping pins exactly once" "$(cat "$DISPATCH_LOG")"
fi
grep -Fq '"+pop' "$DISPATCH_LOG" ||
  fail "popping tags the window" "$(cat "$DISPATCH_LOG")"
pass "popping a tiled window floats, sizes, pins, and tags it"

# An already-floating window keeps its state: no float toggle, so the resize
# can never land on a tiled window and rewrite the dwindle split.
run_pop '{"address":"0x2","pinned":false,"floating":true}'
if grep -Fq 'action = "toggle"' "$DISPATCH_LOG"; then
  fail "popping an already-floating window must not toggle floating" "$(cat "$DISPATCH_LOG")"
fi
grep -Fq 'window.resize' "$DISPATCH_LOG" ||
  fail "an already-floating window still gets the pop size" "$(cat "$DISPATCH_LOG")"
grep -Fq '"+pop' "$DISPATCH_LOG" ||
  fail "an already-floating window still gets tagged as popped" "$(cat "$DISPATCH_LOG")"
pass "popping an already-floating window skips the float toggle"

# An explicit position replaces the centering step for both entry states.
run_pop '{"address":"0x3","pinned":false,"floating":true}' 800 600 20 30
grep -Fq 'window.move' "$DISPATCH_LOG" ||
  fail "an explicit x/y moves the window" "$(cat "$DISPATCH_LOG")"
if grep -Fq 'window.center' "$DISPATCH_LOG"; then
  fail "an explicit x/y must not also center" "$(cat "$DISPATCH_LOG")"
fi
pass "an explicit x/y moves instead of centering"

# The pinned branch is the unpick path and stays untouched by the guard.
run_pop '{"address":"0x4","pinned":true,"floating":true}'
[[ $(grep -c . "$DISPATCH_LOG") == 3 ]] || fail "a pinned window runs exactly three dispatches" "$(cat "$DISPATCH_LOG")"
if grep -Fq 'window.resize' "$DISPATCH_LOG"; then
  fail "unpinning never resizes" "$(cat "$DISPATCH_LOG")"
fi
pass "a pinned window unpins, tiles, and drops the tag without resizing"

# No active window is a no-op.
run_pop ''
[[ ! -s $DISPATCH_LOG ]] || fail "no active window dispatches nothing" "$(cat "$DISPATCH_LOG")"
pass "no active window dispatches nothing"
