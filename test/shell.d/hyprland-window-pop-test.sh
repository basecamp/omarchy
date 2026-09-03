#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/hyprctl" <<'BASH'
#!/bin/bash

set -euo pipefail

if [[ $1 == "activewindow" && $2 == "-j" ]]; then
  cat "$HYPR_STATE"
  exit 0
fi

if [[ $1 == "dispatch" ]]; then
  command="$*"
  printf '%s\n' "$command" >>"$HYPRCTL_LOG"

  update_state() {
    local filter="$1"
    local next_state="$HYPR_STATE.next"

    jq "$filter" "$HYPR_STATE" >"$next_state"
    mv "$next_state" "$HYPR_STATE"
  }

  case "$command" in
    *'hl.dsp.window.float('*|*' togglefloating '*)
      update_state '.floating = (.floating | not)'
      ;;
    *'hl.dsp.window.pin('*|*' pin '*)
      update_state '.pinned = (.pinned | not)'
      ;;
    *'tag = "+pop"'*|*' +pop '*)
      update_state '.tags = (((.tags // []) + ["pop*"]) | unique)'
      ;;
    *'tag = "-pop"'*|*' -pop '*)
      update_state '.tags = [(.tags // [])[] | select(sub("\\*$"; "") != "pop")]'
      ;;
  esac

  exit 0
fi

exit 1
BASH
chmod +x "$tmpdir/hyprctl"

state="$tmpdir/state.json"
log="$tmpdir/hyprctl.log"
cat >"$state" <<'JSON'
{
  "address": "0x1",
  "floating": false,
  "pinned": false,
  "tags": []
}
JSON

run_pop() {
  PATH="$tmpdir:$ROOT/bin:$PATH" HYPR_STATE="$state" HYPRCTL_LOG="$log" \
    "$ROOT/bin/omarchy-hyprland-window-pop"
}

run_float_toggle() {
  PATH="$tmpdir:$ROOT/bin:$PATH" HYPR_STATE="$state" HYPRCTL_LOG="$log" \
    "$ROOT/bin/omarchy-hyprland-window-float-toggle"
}

assert_state() {
  local filter="$1"
  local description="$2"

  jq -e "$filter" "$state" >/dev/null || fail "$description" "$(cat "$state")"
  pass "$description"
}

run_pop
assert_state '.floating == true and .pinned == true and any(.tags[]; sub("\\*$"; "") == "pop")' \
  "pop changes a tiled window into the pop state"

run_float_toggle
assert_state '.floating == false and .pinned == false and ([.tags[] | sub("\\*$"; "")] | index("pop")) == null' \
  "floating toggle exits pop mode as a tiled window"

run_float_toggle
assert_state '.floating == true and .pinned == false and ([.tags[] | sub("\\*$"; "")] | index("pop")) == null' \
  "floating toggle changes a normal window to floating"

run_pop
assert_state '.floating == true and .pinned == true and any(.tags[]; sub("\\*$"; "") == "pop")' \
  "pop keeps a floating window floating while entering pop mode"

run_float_toggle
assert_state '.floating == false and .pinned == false and ([.tags[] | sub("\\*$"; "")] | index("pop")) == null' \
  "floating toggle exits pop mode as a tiled window regardless of entry state"

run_pop
run_pop
assert_state '.floating == false and .pinned == false and ([.tags[] | sub("\\*$"; "")] | index("pop")) == null' \
  "pop toggles cleanly between the tiled and pop states"

grep -Fq 'o.bind("SUPER + T", "Toggle window floating/tiling", "omarchy-hyprland-window-float-toggle")' \
  "$ROOT/default/hypr/bindings/tiling.lua" || fail "SUPER + T uses the pop-aware floating toggle"
pass "SUPER + T uses the pop-aware floating toggle"
