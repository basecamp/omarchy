#!/bin/bash

source "$(dirname "$0")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/hyprctl" <<'BASH'
#!/bin/bash

if [[ $1 == "activewindow" && $2 == "-j" ]]; then
  printf '%s\n' "$HYPR_ACTIVE_WINDOW"
  exit 0
fi

if [[ $1 == "monitors" && $2 == "-j" ]]; then
  printf '%s\n' "$HYPR_MONITORS"
  exit 0
fi

if [[ $1 == "-j" && $2 == "getoption" && $3 == "general:gaps_out" ]]; then
  printf '{"css":"10 10 10 10"}\n'
  exit 0
fi

if [[ $1 == "-j" && $2 == "getoption" && $3 == "general:border_size" ]]; then
  printf '{"int":2}\n'
  exit 0
fi

if [[ $1 == "dispatch" ]]; then
  printf '%s\n' "$*" >>"$HYPRCTL_LOG"
  exit 0
fi

exit 1
BASH
chmod +x "$tmpdir/hyprctl"

log="$tmpdir/hyprctl.log"
active='{"address":"abc123","monitor":0,"pinned":false}'

run_pop() {
  >"$log"
  PATH="$tmpdir:$PATH" HYPRCTL_LOG="$log" HYPR_ACTIVE_WINDOW="$active" HYPR_MONITORS="$1" \
    "$ROOT/bin/omarchy-hyprland-window-pop" "${@:2}"
}

assert_resize() {
  grep -Fq "x = $1, y = $2" "$log" || fail "$3" "$(cat "$log")"
  pass "$3"
}

run_pop '[{"id":0,"width":2880,"height":1800,"scale":2,"transform":0,"reserved":[0,26,0,0]}]'
assert_resize 1300 850 "pop height fits inside the work area gaps and borders"

run_pop '[{"id":0,"width":3840,"height":2160,"scale":2,"transform":0,"reserved":[0,26,0,0]}]'
assert_resize 1300 900 "pop keeps its preferred size when the work area is large enough"

run_pop '[{"id":0,"width":2560,"height":1440,"scale":1.6,"transform":3,"reserved":[0,35,0,0]}]'
assert_resize 876 900 "pop accounts for monitor scale, rotation, gaps, and borders"

run_pop '[{"id":0,"width":2880,"height":1800,"scale":2,"transform":0,"reserved":[0,0,0,26]}]'
assert_resize 1300 850 "pop subtracts a bottom reserved edge from the height"

run_pop '[{"id":0,"width":2880,"height":1800,"scale":2,"transform":0,"reserved":[200,0,0,0]}]'
assert_resize 1216 876 "pop subtracts a left reserved edge from the width"

run_pop '[{"id":0,"width":2880,"height":1800,"scale":2,"transform":0,"reserved":[0,26,0,0]}]' 1500 1000
assert_resize 1500 1000 "pop preserves explicitly requested dimensions"

run_pop '[{"id":0,"width":2880,"height":1800,"scale":2,"transform":0,"reserved":[0,26,0,0]}]' 1200
assert_resize 1200 850 "pop fits an omitted height while preserving an explicit width"

run_pop '[]'
assert_resize 1300 900 "pop retains its defaults when monitor information is unavailable"

run_pop '[{"id":0,"width":2880,"height":1800,"scale":0,"transform":0,"reserved":[0,26,0,0]}]'
assert_resize 1300 900 "pop retains its defaults when monitor geometry is invalid"
