echo "Move a switched-off laptop display into the display overrides"

# Every display setting now lives in ~/.local/state/omarchy/display-overrides.json,
# with the Hyprland rules generated from it. A laptop panel switched off with
# SUPER+CTRL+DEL used to be recorded as its own flag file instead, so carry that
# across and drop the file.
#
# Ordering matters more than usual here: a laptop panel switched off while
# docked, then undocked, boots to a dark screen, and the only thing that rescues
# it is omarchy-hw-recover-internal-monitor. That command reads both locations,
# so a machine part-way through this is still recoverable — but the old file is
# removed only after the new record has been written and read back, so an
# interrupted run leaves the machine exactly as it was rather than with the
# display off and nothing saying so.

flag="$HOME/.local/state/omarchy/toggles/hypr/internal-monitor-disable.lua"
[[ -f $flag ]] || exit 0

internal=$(sed -nE 's/^hl\.monitor\(\{ output = "([^"]+)".*/\1/p' "$flag" | head -1)
if [[ -z $internal ]]; then
  echo "  could not read the display name from $flag, leaving it alone"
  exit 0
fi

omarchy-hyprland-monitor-override set "$internal" disabled true

if [[ $(omarchy-hyprland-monitor-override get "$internal" disabled) != "true" ]]; then
  echo "  could not record $internal as switched off, leaving $flag in place"
  exit 0
fi

rm -f "$flag"
echo "  $internal is now recorded in the display overrides"
