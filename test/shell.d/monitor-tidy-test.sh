#!/bin/bash

# Covers omarchy-hyprland-monitor-tidy, which re-packs displays after a scale or
# rotation change resizes one of them. Layouts are described through
# OMARCHY_MONITOR_JSON so none of this needs a compositor.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command jq

TIDY="$ROOT/bin/omarchy-hyprland-monitor-tidy"

assert_equal() {
  local actual="$1" expected="$2" description="$3"

  if [[ $actual == "$expected" ]]; then
    pass "$description"
  else
    fail "$description" "expected: $expected
actual:   $actual"
  fi
}

tidy() {
  OMARCHY_MONITOR_JSON="$1" "$TIDY" "${@:2}" 2>&1 || true
}

tidy_status() {
  OMARCHY_MONITOR_JSON="$1" "$TIDY" "${@:2}" >/dev/null 2>&1 && echo 0 || echo $?
}

# Two 4K displays at scale 1.6 are 2400x1350 each, so one at 0 and one at 2400
# sit exactly edge to edge.
ALIGNED='[
  {"name":"DP-1","x":0,"y":0,"width":3840,"height":2160,"scale":1.6,"transform":0},
  {"name":"DP-2","x":2400,"y":0,"width":3840,"height":2160,"scale":1.6,"transform":0}
]'

assert_equal "$(tidy_status "$ALIGNED" check)" "0" "tidy accepts a layout that already sits edge to edge"
assert_equal "$(tidy "$ALIGNED" check)" "No displays overlap." "tidy says so when nothing overlaps"

# The reported case: the same displays at scale 1.25 are 3072 wide, so the one
# pinned at 2400 is overrun by 672.
OVERLAPPING='[
  {"name":"DP-1","x":0,"y":0,"width":3840,"height":2160,"scale":1.25,"transform":0},
  {"name":"DP-2","x":2400,"y":0,"width":3840,"height":2160,"scale":1.25,"transform":0}
]'

assert_equal "$(tidy_status "$OVERLAPPING" check)" "1" "tidy reports an overlapping layout"
assert_equal \
  "$(tidy "$OVERLAPPING" check | tail -1)" \
  "  DP-1 and DP-2 overlap by 672x1728 logical pixels" \
  "tidy measures the overlap"
assert_equal \
  "$(tidy "$OVERLAPPING" --dry-run | tail -1)" \
  "  DP-2: x 2400 -> 3072" \
  "tidy moves the second display clear of the first"

# hyprctl reports the mode rather than the rotated result, so a quarter turn has
# to swap the axes before any of this arithmetic works. Rotated, DP-2 is 1350
# wide rather than 2400. Sitting at 3000 it clears DP-1 entirely, so there is
# nothing to fix -- a gap is not an error, and moving a display nobody asked to
# move is how a deliberate layout gets destroyed.
ROTATED_CLEAR='[
  {"name":"DP-1","x":0,"y":0,"width":3840,"height":2160,"scale":1.6,"transform":0},
  {"name":"DP-2","x":3000,"y":0,"width":3840,"height":2160,"scale":1.6,"transform":1}
]'
assert_equal "$(tidy_status "$ROTATED_CLEAR" check)" "0" "tidy leaves a gap after a rotation alone"

# Unrotated, the same display would be 2400 wide and would overrun DP-1 -- which
# is what proves the axis swap is being applied rather than the raw mode.
ROTATED_COLLIDING='[
  {"name":"DP-1","x":0,"y":0,"width":3840,"height":2160,"scale":1.6,"transform":0},
  {"name":"DP-2","x":1800,"y":0,"width":3840,"height":2160,"scale":1.6,"transform":1}
]'
assert_equal \
  "$(tidy "$ROTATED_COLLIDING" --dry-run | tail -1)" \
  "  DP-2: x 1800 -> 2400" \
  "tidy accounts for a quarter turn swapping the axes"

# Stacked displays must stay stacked; packing them along x would silently
# rearrange the desktop.
STACKED='[
  {"name":"DP-1","x":0,"y":0,"width":3840,"height":2160,"scale":1.6,"transform":0},
  {"name":"DP-2","x":0,"y":2000,"width":3840,"height":2160,"scale":1.6,"transform":0}
]'

assert_equal "$(tidy_status "$STACKED" check)" "0" "tidy leaves a spaced-out stack alone"

# Overlapping vertically, though, must be resolved along the vertical axis
# rather than shoved sideways.
STACKED_OVERLAP='[
  {"name":"DP-1","x":0,"y":0,"width":3840,"height":2160,"scale":1.6,"transform":0},
  {"name":"DP-2","x":0,"y":900,"width":3840,"height":2160,"scale":1.6,"transform":0}
]'
assert_equal \
  "$(tidy "$STACKED_OVERLAP" --dry-run | tail -1)" \
  "  DP-2: y 900 -> 1350" \
  "tidy resolves a stacked overlap along the axis it was already on"

# The anchor never moves, so tidying does not drag the whole desktop.
OFFSET='[
  {"name":"DP-1","x":500,"y":300,"width":3840,"height":2160,"scale":1.6,"transform":0},
  {"name":"DP-2","x":1000,"y":300,"width":3840,"height":2160,"scale":1.6,"transform":0}
]'

assert_equal \
  "$(tidy "$OFFSET" --dry-run | tail -1)" \
  "  DP-2: x 1000 -> 2900" \
  "tidy leaves the first display where it is"

# A single display cannot overlap anything, and a disabled one is not part of
# the layout.
SINGLE='[{"name":"DP-1","x":0,"y":0,"width":3840,"height":2160,"scale":1.6,"transform":0}]'
assert_equal "$(tidy_status "$SINGLE" check)" "0" "tidy accepts a single display"

DISABLED='[
  {"name":"DP-1","x":0,"y":0,"width":3840,"height":2160,"scale":1.25,"transform":0},
  {"name":"DP-2","x":2400,"y":0,"width":3840,"height":2160,"scale":1.25,"transform":0,"disabled":true}
]'
assert_equal "$(tidy_status "$DISABLED" check)" "0" "tidy ignores a disabled display"

# --intended positions displays for the layout a change is about to produce,
# rather than the current one. Callers use it to move neighbours clear *before*
# growing a display, because Hyprland notifies the instant two displays overlap
# and that warning stays on screen after the layout is valid again.
CURRENT_16='[
  {"name":"DP-1","x":0,"y":0,"width":3840,"height":2160,"scale":1.6,"transform":0},
  {"name":"DP-2","x":2400,"y":0,"width":3840,"height":2160,"scale":1.6,"transform":0}
]'
INTENDED_125='[
  {"name":"DP-1","x":0,"y":0,"width":3840,"height":2160,"scale":1.25,"transform":0},
  {"name":"DP-2","x":2400,"y":0,"width":3840,"height":2160,"scale":1.25,"transform":0}
]'

# The current layout is fine, so without --intended there is nothing to do.
assert_equal "$(tidy_status "$CURRENT_16" check)" "0" "tidy sees nothing wrong with the layout before the change"

# Asked about the layout the change will produce, it moves the neighbour clear.
assert_equal \
  "$(OMARCHY_MONITOR_JSON="$CURRENT_16" "$TIDY" --intended "$INTENDED_125" --dry-run 2>&1 | tail -1)" \
  "  DP-2: x 2400 -> 3072" \
  "tidy plans for the layout a pending change will produce"

# A mirrored display repeats another one and shares its position. Counting it as
# its own area reads as a total overlap, and tidying then moves the display
# being mirrored out from under it, breaking the mirror on the next scale
# change -- mirroring is a first-class Omarchy feature (projectors, clamshell).
MIRRORED='[
  {"name":"eDP-1","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"mirrorOf":"none"},
  {"name":"HDMI-A-1","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"mirrorOf":"eDP-1"}
]'
assert_equal "$(tidy_status "$MIRRORED" check)" "0" "tidy leaves a mirrored pair alone"

# Three displays in a row pack cumulatively, each against the one before it.
TRIPLE='[
  {"name":"DP-1","x":0,"y":0,"width":3840,"height":2160,"scale":1.25,"transform":0},
  {"name":"DP-2","x":2400,"y":0,"width":3840,"height":2160,"scale":1.25,"transform":0},
  {"name":"DP-3","x":4800,"y":0,"width":3840,"height":2160,"scale":1.25,"transform":0}
]'
assert_equal \
  "$(tidy "$TRIPLE" --dry-run | grep -- '->' | sort | tr -s ' \n' ' ')" \
  " DP-2: x 2400 -> 3072 DP-3: x 4800 -> 6144 " \
  "tidy packs three displays cumulatively"

# An L-shaped layout is valid: nothing overlaps, the second row simply sits
# below. Displays only pack against ones they stand beside, so a second row is
# not flattened into the first.
LSHAPE='[
  {"name":"DP-1","x":0,"y":0,"width":3840,"height":2160,"scale":1.6,"transform":0},
  {"name":"DP-2","x":2400,"y":0,"width":3840,"height":2160,"scale":1.6,"transform":0},
  {"name":"DP-3","x":0,"y":1350,"width":3840,"height":2160,"scale":1.6,"transform":0}
]'
assert_equal "$(tidy_status "$LSHAPE" check)" "0" "tidy leaves a valid L-shaped layout alone"

# A tall display beside two stacked ones shares the cross axis with both rows.
# Grouping displays transitively on that basis dragged the lower row sideways,
# even though nothing overlapped. Only collisions may move a display.
SPANNING='[
  {"name":"A","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"C","x":0,"y":1080,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"D","x":1920,"y":0,"width":1920,"height":2160,"scale":1,"transform":0}
]'
assert_equal "$(tidy_status "$SPANNING" check)" "0" "tidy leaves a row beside a full-height display alone"

# A display sitting entirely inside another still has to be moved clear.
CONTAINED='[
  {"name":"BIG","x":0,"y":0,"width":3840,"height":2160,"scale":1,"transform":0},
  {"name":"SMALL","x":500,"y":500,"width":800,"height":600,"scale":1,"transform":0}
]'
assert_equal "$(tidy_status "$CONTAINED" check)" "1" "tidy reports a display contained inside another"

# Tidying must settle in one pass: whatever it proposes has to leave a layout it
# then considers finished, or the callers would fight it on every change.
assert_idempotent() {
  local description="$1" layout="$2"
  local settled
  settled=$(OMARCHY_MONITOR_JSON="$layout" python3 -c '
import json, os, subprocess, sys
monitors = json.loads(os.environ["OMARCHY_MONITOR_JSON"])
result = subprocess.run([sys.argv[1], "--dry-run"], capture_output=True, text=True,
                        env=dict(os.environ))
for line in result.stdout.splitlines():
    if "->" not in line:
        continue
    name = line.split(":")[0].strip()
    axis = line.split(":")[1].strip().split()[0]
    for monitor in monitors:
        if monitor["name"] == name:
            monitor[axis] = float(line.split("->")[1])
print(json.dumps(monitors))
' "$TIDY")

  assert_equal "$(tidy_status "$settled" check)" "0" "$description"
}

assert_idempotent "tidy settles a contained display in one pass" "$CONTAINED"
assert_idempotent "tidy settles three overlapping displays in one pass" '[
  {"name":"A","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"B","x":1000,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"C","x":2000,"y":0,"width":1920,"height":1080,"scale":1,"transform":0}
]'
assert_idempotent "tidy settles a stacked overlap in one pass" "$STACKED_OVERLAP"

# --------------------------------------------------------------------------
# Command line surface
# --------------------------------------------------------------------------

# The usage text is the only documentation a user gets, so --help has to reach
# stdout and succeed -- a help screen on stderr behind a non-zero exit is what
# breaks `omarchy hyprland monitor tidy --help | less`.
for flag in -h --help; do
  help_out=$(OMARCHY_MONITOR_JSON='[]' "$TIDY" "$flag" 2>/dev/null) && help_status=0 || help_status=$?
  assert_equal "$help_status" "0" "tidy exits 0 for $flag"
  case $help_out in
  *"Usage:"*check*apply*) pass "tidy describes both actions in $flag" ;;
  *) fail "tidy describes both actions in $flag" "got: $help_out" ;;
  esac
done

# An unrecognised flag must be refused rather than silently ignored; a caller
# that typos --dry-run would otherwise move the user's displays for real.
unknown_out=$(OMARCHY_MONITOR_JSON='[]' "$TIDY" --no-such-flag 2>&1 >/dev/null) || true
assert_equal "$(tidy_status '[]' --no-such-flag)" "1" "tidy rejects an unknown flag"
case $unknown_out in
*"Usage:"*) pass "tidy explains itself on stderr when refusing a flag" ;;
*) fail "tidy explains itself on stderr when refusing a flag" "got: $unknown_out" ;;
esac

# apply is the default action, so naming it explicitly must not change anything.
assert_equal \
  "$(tidy "$OVERLAPPING" apply --dry-run | tail -1)" \
  "$(tidy "$OVERLAPPING" --dry-run | tail -1)" \
  "tidy treats apply as the default action"

# No displays at all is what a headless or still-starting session reports.
# Falling over there would break the scale and rotation commands that call this
# unconditionally.
assert_equal "$(tidy_status '[]' check)" "0" "tidy accepts an empty monitor listing"
assert_equal "$(tidy_status '[]' --dry-run)" "0" "tidy has nothing to do with no displays"

# --------------------------------------------------------------------------
# Layout arithmetic
# --------------------------------------------------------------------------

# hyprctl reports the unrotated mode, so every odd transform -- the quarter
# turns, including the flipped ones (4-7) -- has to swap width and height.
# Getting only transform 1 right is the easy half-fix.
for transform in 0 1 2 3 4 5 6 7; do
  ROTATION_CASE="[
    {\"name\":\"A\",\"x\":0,\"y\":0,\"width\":1920,\"height\":1080,\"scale\":1,\"transform\":$transform},
    {\"name\":\"B\",\"x\":1000,\"y\":0,\"width\":1920,\"height\":1080,\"scale\":1,\"transform\":0}
  ]"
  if ((transform % 2)); then
    expected="  B: x 1000 -> 1080"
  else
    expected="  B: x 1000 -> 1920"
  fi
  assert_equal "$(tidy "$ROTATION_CASE" --dry-run | tail -1)" "$expected" \
    "tidy swaps the axes for transform $transform only when it is a quarter turn"
done

# hyprctl omits scale on some paths and can report 0 while a display is coming
# up. Either has to read as 1x rather than dividing by zero or by nothing.
NO_SCALE='[
  {"name":"A","x":0,"y":0,"width":1920,"height":1080,"transform":0},
  {"name":"B","x":1000,"y":0,"width":1920,"height":1080,"transform":0}
]'
assert_equal "$(tidy "$NO_SCALE" --dry-run | tail -1)" "  B: x 1000 -> 1920" \
  "tidy treats a missing scale as 1x"

ZERO_SCALE='[
  {"name":"A","x":0,"y":0,"width":1920,"height":1080,"scale":0,"transform":0},
  {"name":"B","x":1000,"y":0,"width":1920,"height":1080,"scale":0,"transform":0}
]'
assert_equal "$(tidy "$ZERO_SCALE" --dry-run | tail -1)" "  B: x 1000 -> 1920" \
  "tidy survives a scale of 0"

# 3840 / 1.5 is exactly 2560, so a fractional scale must divide the mode rather
# than being rounded to an integer first.
SCALED_15='[
  {"name":"A","x":0,"y":0,"width":3840,"height":2160,"scale":1.5,"transform":0},
  {"name":"B","x":1000,"y":0,"width":3840,"height":2160,"scale":1.5,"transform":0}
]'
assert_equal "$(tidy "$SCALED_15" --dry-run | tail -1)" "  B: x 1000 -> 2560" \
  "tidy divides the mode by a fractional scale"

# Hyprland's coordinate space is signed: a display placed left of or above the
# primary has negative coordinates, and arithmetic that assumes non-negative
# positions parks it in the wrong place.
NEGATIVE='[
  {"name":"A","x":-1920,"y":-1080,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"B","x":-1000,"y":-1080,"width":1920,"height":1080,"scale":1,"transform":0}
]'
assert_equal "$(tidy "$NEGATIVE" --dry-run | tail -1)" "  B: x -1000 -> 0" \
  "tidy handles displays at negative coordinates"

# --------------------------------------------------------------------------
# Overlap detection
# --------------------------------------------------------------------------

# Sharing an edge is the goal state, not a collision. Treating >= as an overlap
# would make every tidied layout report as broken forever after.
CORNER_TOUCH='[
  {"name":"A","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"B","x":1920,"y":1080,"width":1920,"height":1080,"scale":1,"transform":0}
]'
assert_equal "$(tidy_status "$CORNER_TOUCH" check)" "0" "tidy does not call a shared corner an overlap"

# The reported size must be the real intersection on both axes, not the offset
# on one of them; a diagonal overlap is where those two differ.
DIAGONAL='[
  {"name":"A","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"B","x":1720,"y":1000,"width":1920,"height":1080,"scale":1,"transform":0}
]'
assert_equal "$(tidy "$DIAGONAL" check | tail -1)" \
  "  A and B overlap by 200x80 logical pixels" \
  "tidy measures a diagonal overlap on both axes"

# One display fully inside another intersects by the whole of the smaller one.
assert_equal "$(tidy "$CONTAINED" check | tail -1)" \
  "  BIG and SMALL overlap by 800x600 logical pixels" \
  "tidy measures a containment as the whole inner display"

# Every colliding pair has to be listed, not just the first: a user fixing them
# by hand needs the full picture, and three displays in a heap is three pairs.
PILE='[
  {"name":"A","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"B","x":100,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"C","x":200,"y":0,"width":1920,"height":1080,"scale":1,"transform":0}
]'
assert_equal "$(tidy "$PILE" check | grep -c 'overlap by')" "3" \
  "tidy reports every overlapping pair"

# --------------------------------------------------------------------------
# Run grouping: only displays that actually collide may move
# --------------------------------------------------------------------------

# Two independent rows. The bottom row overlaps; the top row is already right.
# Grouping displays by anything looser than a real collision drags the innocent
# row along with the fix.
TWO_ROWS='[
  {"name":"TL","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"TR","x":1920,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"BL","x":0,"y":1080,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"BR","x":1000,"y":1080,"width":1920,"height":1080,"scale":1,"transform":0}
]'
assert_equal "$(tidy "$TWO_ROWS" --dry-run | grep -c '\->')" "1" \
  "tidy moves only the display that collides, not the whole row"
assert_equal "$(tidy "$TWO_ROWS" --dry-run | tail -1)" "  BR: x 1000 -> 1920" \
  "tidy fixes the colliding row in place"

# A deliberately distant display is a spaced layout, not a gap to close.
DISTANT='[
  {"name":"A","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"B","x":1000,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"FAR","x":9000,"y":0,"width":1920,"height":1080,"scale":1,"transform":0}
]'
assert_equal "$(tidy "$DISTANT" --dry-run | grep -c '\->')" "1" \
  "tidy does not drag a distant display in to close a gap"

# --------------------------------------------------------------------------
# Mirrored and disabled displays
# --------------------------------------------------------------------------

# hyprctl reports mirrorOf as the string "none", but a null slips through some
# paths; both mean the same thing and neither may read as "mirrors a display
# called none".
MIRROR_NULL='[
  {"name":"A","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"mirrorOf":null},
  {"name":"M","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"mirrorOf":"A"}
]'
assert_equal "$(tidy_status "$MIRROR_NULL" check)" "0" "tidy reads a null mirrorOf as not mirroring"

# A mirror shares its source's position by definition. It must never be given a
# move of its own, even while the rest of the layout is being repacked.
MIRROR_PLUS_OVERLAP='[
  {"name":"A","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"mirrorOf":"none"},
  {"name":"M","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"mirrorOf":"A"},
  {"name":"B","x":1000,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"mirrorOf":"none"}
]'
assert_equal "$(tidy "$MIRROR_PLUS_OVERLAP" --dry-run | grep -c '\->')" "1" \
  "tidy never plans a move for a mirrored display"
assert_equal "$(tidy "$MIRROR_PLUS_OVERLAP" --dry-run | tail -1)" "  B: x 1000 -> 1920" \
  "tidy repacks around a mirrored pair without disturbing it"

# A disabled display keeps its stale coordinates in hyprctl's listing. Counting
# them invents collisions and moves live displays to dodge a dark panel.
DISABLED_IN_THE_WAY='[
  {"name":"A","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"OFF","x":100,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"disabled":true},
  {"name":"B","x":1000,"y":0,"width":1920,"height":1080,"scale":1,"transform":0}
]'
assert_equal "$(tidy "$DISABLED_IN_THE_WAY" --dry-run | grep -c '\->')" "1" \
  "tidy plans no move for a disabled display"
assert_equal "$(tidy "$DISABLED_IN_THE_WAY" --dry-run | tail -1)" "  B: x 1000 -> 1920" \
  "tidy ignores a disabled display sitting between two live ones"

# Everything but one display mirrored or off is a clamshell/projector session:
# one effective area, so nothing can collide.
ONLY_ONE_EFFECTIVE='[
  {"name":"eDP-1","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"disabled":true},
  {"name":"HDMI-A-1","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"mirrorOf":"none"},
  {"name":"HDMI-A-2","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"mirrorOf":"HDMI-A-1"}
]'
assert_equal "$(tidy_status "$ONLY_ONE_EFFECTIVE" check)" "0" \
  "tidy accepts a clamshell layout with one effective display"

# --------------------------------------------------------------------------
# --intended planning
# --------------------------------------------------------------------------

# Both spellings of the flag have to mean the same thing; scaling and rotation
# call it one way and a user may well type the other.
assert_equal \
  "$(OMARCHY_MONITOR_JSON="$CURRENT_16" "$TIDY" --intended="$INTENDED_125" --dry-run 2>&1 | tail -1)" \
  "$(OMARCHY_MONITOR_JSON="$CURRENT_16" "$TIDY" --intended "$INTENDED_125" --dry-run 2>&1 | tail -1)" \
  "tidy accepts --intended=VALUE and --intended VALUE alike"

# --intended replaces the current layout outright. If the current one still had
# a say, a caller shrinking a display would be told to fix an overlap that is
# about to disappear on its own.
assert_equal \
  "$(OMARCHY_MONITOR_JSON="$OVERLAPPING" "$TIDY" --intended "$ALIGNED" --dry-run 2>&1)" \
  "" \
  "tidy plans nothing when the pending change resolves the current overlap"
assert_equal \
  "$(OMARCHY_MONITOR_JSON="$OVERLAPPING" "$TIDY" check --intended "$ALIGNED" 2>&1)" \
  "No displays overlap." \
  "tidy checks the intended layout rather than the current one"

# check and --intended compose, so a caller can ask "will this change break the
# layout?" without applying anything.
assert_equal \
  "$(OMARCHY_MONITOR_JSON="$ALIGNED" "$TIDY" check --intended "$OVERLAPPING" >/dev/null 2>&1 && echo 0 || echo 1)" \
  "1" \
  "tidy reports a pending change that would overlap"

# An explicitly empty --intended= carries no layout, so the current one is all
# there is to work from; dropping to no displays at all would silently skip the
# tidy a caller asked for.
assert_equal \
  "$(OMARCHY_MONITOR_JSON="$OVERLAPPING" "$TIDY" --intended= --dry-run 2>&1 | tail -1)" \
  "  DP-2: x 2400 -> 3072" \
  "tidy falls back to the current layout for an empty --intended="

# --------------------------------------------------------------------------
# Properties over generated layouts
# --------------------------------------------------------------------------

# An exact tiling of a rectangle has no gap and no overlap anywhere, so there is
# nothing for tidy to do -- whatever shape it happens to be. Grouping displays
# transitively (a tall display "connecting" two stacked neighbours) used to
# flatten such layouts into a row and tear a real hole in the desktop.
tilings_disturbed=$(python3 - "$TIDY" <<'PY'
import json, os, random, subprocess, sys

tidy = sys.argv[1]


def carve(rect, depth, out):
    x, y, w, h = rect
    if depth == 0 or random.random() < 0.3 or (w < 2 and h < 2):
        out.append(rect)
        return
    if w >= 2 and (h < 2 or random.random() < 0.5):
        cut = random.randint(1, w - 1)
        carve((x, y, cut, h), depth - 1, out)
        carve((x + cut, y, w - cut, h), depth - 1, out)
    else:
        cut = random.randint(1, h - 1)
        carve((x, y, w, cut), depth - 1, out)
        carve((x, y + cut, w, h - cut), depth - 1, out)


disturbed = 0
for seed in range(120):
    random.seed(seed)
    cells = []
    carve((0, 0, 8, 8), 3, cells)
    if len(cells) < 2:
        continue
    layout = [
        {"name": "M%d" % i, "x": x * 240, "y": y * 240,
         "width": w * 240, "height": h * 240, "scale": 1, "transform": 0}
        for i, (x, y, w, h) in enumerate(cells)
    ]
    env = dict(os.environ, OMARCHY_MONITOR_JSON=json.dumps(layout))
    result = subprocess.run([tidy, "--dry-run"], capture_output=True, text=True, env=env)
    if "->" in result.stdout:
        disturbed += 1
        if disturbed == 1:
            print(json.dumps(layout), result.stdout, file=sys.stderr)
print(disturbed)
PY
)
assert_equal "$tilings_disturbed" "0" "tidy never disturbs an exact tiling of the desktop"

# Whatever tidy proposes has to leave a layout with no overlaps in it -- judged
# independently here rather than by asking tidy again, so a shared blind spot in
# the overlap test cannot make both passes agree on a broken result. A second
# pass proposing further moves is the visible symptom: the display jumps, the
# success message prints, and Hyprland still says the layout is wrong.
unsettled=$(python3 - "$TIDY" <<'PY'
import json, os, random, subprocess, sys

tidy = sys.argv[1]
MODES = [(1920, 1080), (2560, 1440), (3840, 2160), (1280, 1024), (3440, 1440)]
SCALES = [1, 1.25, 1.5, 1.6, 2, 2.5]


def run(layout, *args):
    env = dict(os.environ, OMARCHY_MONITOR_JSON=json.dumps(layout))
    return subprocess.run([tidy, *args], capture_output=True, text=True, env=env)


def moves(stdout):
    found = {}
    for line in stdout.splitlines():
        if "->" not in line:
            continue
        name, rest = line.split(":", 1)
        axis = rest.strip().split()[0]
        found.setdefault(name.strip(), {})[axis] = float(line.split("->")[1])
    return found


def rects(layout):
    out = []
    for monitor in layout:
        scale = float(monitor.get("scale") or 1) or 1
        w = monitor["width"] / scale
        h = monitor["height"] / scale
        if monitor["transform"] % 2:
            w, h = h, w
        out.append((monitor["name"], monitor["x"], monitor["y"], w, h))
    return out


def collisions(layout):
    boxes = rects(layout)
    hits = []
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            _, ax, ay, aw, ah = boxes[i]
            _, bx, by, bw, bh = boxes[j]
            if min(ax + aw, bx + bw) - max(ax, bx) > 0.5 and \
               min(ay + ah, by + bh) - max(ay, by) > 0.5:
                hits.append((boxes[i][0], boxes[j][0]))
    return hits


broken = 0
for seed in range(150):
    random.seed(seed + 5000)
    layout = [
        {"name": "M%d" % i,
         "x": random.randrange(-2000, 4000, 80),
         "y": random.randrange(-2000, 3000, 80),
         "width": mode[0], "height": mode[1],
         "scale": random.choice(SCALES),
         "transform": random.randrange(0, 8)}
        for i, mode in enumerate(random.choice(MODES) for _ in range(random.randint(2, 5)))
    ]
    planned = moves(run(layout, "--dry-run").stdout)
    settled = [dict(m) for m in layout]
    for monitor in settled:
        for axis, value in planned.get(monitor["name"], {}).items():
            monitor[axis] = value
    second = run(settled, "check")
    if collisions(settled) or second.returncode != 0:
        broken += 1
        if broken == 1:
            print(json.dumps(layout), collisions(settled), second.stdout, file=sys.stderr)
print(broken)
PY
)
assert_equal "$unsettled" "0" "tidy leaves no overlaps behind and settles in a single pass"

# --------------------------------------------------------------------------
# apply, against stand-in hyprctl and monitor-rule commands
# --------------------------------------------------------------------------

# apply is the only path that changes anything, so it is worth exercising --
# but it must never reach the real compositor or the real monitors.lua. Both
# collaborators are invoked by name, so a directory at the front of PATH is
# enough to record the calls instead of making them.
STUB_BIN=$(mktemp -d)
trap 'rm -rf "$STUB_BIN"' EXIT

cat >"$STUB_BIN/hyprctl" <<'STUB'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$TIDY_CALL_LOG"
STUB
cat >"$STUB_BIN/omarchy-hyprland-monitor-rule" <<'STUB'
#!/bin/bash
printf 'rule %s\n' "$*" >>"$TIDY_CALL_LOG"
STUB
chmod +x "$STUB_BIN/hyprctl" "$STUB_BIN/omarchy-hyprland-monitor-rule"

apply_calls() {
  local layout="$1"
  export TIDY_CALL_LOG="$STUB_BIN/log"
  : >"$TIDY_CALL_LOG"
  OMARCHY_MONITOR_JSON="$layout" PATH="$STUB_BIN:$PATH" "$TIDY" "${@:2}" >/dev/null 2>&1 || true
  cat "$TIDY_CALL_LOG"
}

# A layout that is already right must not be "fixed": every write here is a
# monitors.lua edit and a compositor round trip the user did not ask for.
assert_equal "$(apply_calls "$ALIGNED" apply)" "" "tidy applying a settled layout touches nothing"

# --dry-run has to be genuinely inert, or the flag callers use to preview a
# change is itself the change.
assert_equal "$(apply_calls "$OVERLAPPING" apply --dry-run)" "" "tidy --dry-run issues no commands"

# The move has to reach both the compositor (so it takes effect now) and the
# rule file (so it survives a reload). One without the other is a layout that
# silently reverts.
applied=$(apply_calls "$OVERLAPPING" apply)
case $applied in
*'output = "DP-2"'*'position = "3072x0"'*) pass "tidy applies the planned position to the compositor" ;;
*) fail "tidy applies the planned position to the compositor" "got: $applied" ;;
esac
case $applied in
*"rule set DP-2 position=3072x0"*) pass "tidy persists the planned position to the display rule" ;;
*) fail "tidy persists the planned position to the display rule" "got: $applied" ;;
esac
assert_equal "$(printf '%s\n' "$applied" | grep -c '^hyprctl ')" "1" \
  "tidy issues one compositor call per moved display"

# Packing along one axis must leave the other coordinate exactly where it was;
# writing a whole position means it is easy to reset the untouched axis to 0.
OFFSET_STACK='[
  {"name":"A","x":700,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"B","x":700,"y":900,"width":1920,"height":1080,"scale":1,"transform":0}
]'
case $(apply_calls "$OFFSET_STACK" apply) in
*"rule set B position=700x1080"*) pass "tidy preserves the cross-axis coordinate when it repacks" ;;
*) fail "tidy preserves the cross-axis coordinate when it repacks" "got: $(apply_calls "$OFFSET_STACK" apply)" ;;
esac

# apply must be a fixed point: feeding back exactly what it wrote has to leave
# nothing to do. Otherwise the automatic tidy after every scale or rotation
# change fights itself and the display visibly jumps twice.
REAPPLIED='[
  {"name":"DP-1","x":0,"y":0,"width":3840,"height":2160,"scale":1.25,"transform":0},
  {"name":"DP-2","x":3072,"y":0,"width":3840,"height":2160,"scale":1.25,"transform":0}
]'
assert_equal "$(tidy_status "$REAPPLIED" check)" "0" "tidy considers its own applied result finished"
assert_equal "$(apply_calls "$REAPPLIED" apply)" "" "tidy applied a second time changes nothing"

# --intended's whole purpose is that the displays never overlap even for an
# instant. When a clearance pass shifts a column outward, moving the near
# neighbour first drops it on top of the far one until the next call lands --
# so the moves have to be ordered outermost first. Replayed against the live
# geometry, because the resize the caller is clearing space for has not
# happened yet.
CLEARANCE_STACK='[
  {"name":"A","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"B","x":0,"y":1080,"width":1920,"height":1080,"scale":1,"transform":0},
  {"name":"C","x":0,"y":2160,"width":1920,"height":1080,"scale":1,"transform":0}
]'
CLEARANCE_INTENDED=$(jq -c '[.[] | if .name == "A" then (.width = 1920 | .height = 1920) else . end]' <<<"$CLEARANCE_STACK")

assert_equal "$(tidy_status "$CLEARANCE_STACK" check)" "0" \
  "the column the clearance pass starts from is already settled"

CLEARANCE_LOG=$(apply_calls "$CLEARANCE_STACK" apply --intended "$CLEARANCE_INTENDED")
transient=$(python3 - "$CLEARANCE_STACK" "$CLEARANCE_LOG" <<'PY'
import json
import re
import sys

layout = {m["name"]: dict(m) for m in json.loads(sys.argv[1])}
worst = 0

def collide():
    boxes = [(n, m["x"], m["y"], m["width"], m["height"]) for n, m in layout.items()]
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            _, ax, ay, aw, ah = boxes[i]
            _, bx, by, bw, bh = boxes[j]
            h = min(ax + aw, bx + bw) - max(ax, bx)
            v = min(ay + ah, by + bh) - max(ay, by)
            if h > 0 and v > 0:
                yield boxes[i][0], boxes[j][0], h, v

for line in sys.argv[2].splitlines():
    found = re.search(r'output = "([^"]+)".*position = "(-?\d+)x(-?\d+)"', line)
    if not found:
        continue
    name, x, y = found.group(1), int(found.group(2)), int(found.group(3))
    if name in layout:
        layout[name]["x"], layout[name]["y"] = x, y
    for _, _, h, v in collide():
        worst = max(worst, min(h, v))

print(worst)
PY
)
# The two checks below cover defects that are still live in
# bin/omarchy-hyprland-monitor-tidy. `fail` exits on the first one, which would
# hide the second, so they are collected and reported together -- both are
# useful to see at once while the fixes are being written.
outstanding=()

record() {
  local description="$1" detail="$2"

  if [[ -z $detail ]]; then
    pass "$description"
  else
    outstanding+=("$description")
    printf '%s\nnot ok - %s\n' "$detail" "$description" >&2
  fi
}

if [[ $transient == "0" ]]; then
  record "tidy orders a clearance pass so no intermediate state overlaps" ""
else
  record "tidy orders a clearance pass so no intermediate state overlaps" \
    "expected no overlap at any point; two displays overlapped by ${transient}px
between compositor calls:
$CLEARANCE_LOG"
fi

# A flag that takes a value and is given none is a usage error. Spinning
# instead pins a CPU core forever, and callers interpolating an unset variable
# (--intended "$plan") hit it with no way out but SIGKILL.
OMARCHY_MONITOR_JSON='[]' timeout --kill-after=1s 5s "$TIDY" --intended >/dev/null 2>&1 && intended_status=0 || intended_status=$?
if ((intended_status == 124 || intended_status == 137)); then
  record "tidy refuses --intended with no value instead of hanging" \
    "expected a usage error; the command had to be killed (exit $intended_status)"
else
  record "tidy refuses --intended with no value instead of hanging" ""
fi

if ((${#outstanding[@]})); then
  printf 'not ok - %d known defect(s) in omarchy-hyprland-monitor-tidy remain unfixed\n' \
    "${#outstanding[@]}" >&2
  exit 1
fi
