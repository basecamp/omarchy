#!/bin/bash
# omarchy-hook bar-changed <position> <transparent> [previous]
#   position    : top | bottom | left | right  (the edge the bar occupies)
#   transparent : true | false
#   previous    : the edge the bar just moved off of, if it moved (optional)
#
# Keep the window gap on the bar's edge in step with the bar: 0 when the bar is
# transparent (windows sit flush under it) or the same as the other edges when
# opaque. Reads the current gaps_out and only touches two edges: the bar's own
# edge, and the edge the bar just left (restored to the window gap, so a bar that
# moves away from an edge it had flushed doesn't strand it at 0). Every other edge
# is left untouched, so custom gaps, a hand-set zero, and toggles like
# window-no-gaps are all preserved.

position="${1:-top}"
transparent="${2:-false}"
previous="${3:-$position}"

# Allow running from outside the session (the shell normally passes this in) by
# deriving the Hyprland instance signature from the newest instance runtime dir,
# the same way bin/omarchy-restart-shell does.
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hypr_dir=$(find "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2-)
  [[ -n $hypr_dir ]] && export HYPRLAND_INSTANCE_SIGNATURE=${hypr_dir##*/}
fi

# current gaps_out, in CSS order: top right bottom left
read -r top right bottom left < <(hyprctl getoption general:gaps_out -j 2>/dev/null \
  | python3 -c "import sys,json; c=(json.load(sys.stdin).get('css','').split()+['10']*4)[:4]; print(*c)" 2>/dev/null)
for e in top right bottom left; do [[ ${!e} =~ ^[0-9]+$ ]] || printf -v "$e" 10; done

# the window gap = the largest current gap, so an edge left flush doesn't skew it
gap=$top; for v in $right $bottom $left; do (( v > gap )) && gap=$v; done

# restore the edge the bar just moved off of (0 -> the window gap); it's the only
# edge we ever assume was ours to flush, so a hand-set zero elsewhere is left alone
if [[ $previous != "$position" ]]; then
  case "$previous" in
    top)    top=$gap ;;
    bottom) bottom=$gap ;;
    left)   left=$gap ;;
    right)  right=$gap ;;
  esac
fi

# the bar's own edge: 0 when transparent (flush), else the window gap
edge=$gap; [[ $transparent == true ]] && edge=0
case "$position" in
  top)    top=$edge ;;
  bottom) bottom=$edge ;;
  left)   left=$edge ;;
  right)  right=$edge ;;
esac

# omarchy drives Hyprland with the Lua config parser, where `hyprctl keyword` can
# be rejected ("Use eval."); set the gap through the same hl.config() API instead.
hyprctl eval "hl.config({ general = { gaps_out = { top = $top, right = $right, bottom = $bottom, left = $left } } })" >/dev/null 2>&1 || true
