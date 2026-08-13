echo "Pin an existing display mirror to the display it mirrors"

# A mirror rule used to say position = "auto", which only lands on the mirrored
# display while the output stays up: disable and re-enable it and the rule is
# rebuilt from the user's own monitors.lua entry instead, so the two displays
# cover different regions and each shows different content while still
# reporting as mirroring. The rule now pins the source's position, but it is
# only written when mirroring is switched on, so a machine already mirroring
# keeps the old rule until someone happens to toggle it.

flag="$HOME/.local/state/omarchy/toggles/hypr/internal-monitor-mirror.lua"

# Not mirroring, or already pinned by a version that writes the position.
[[ -f $flag ]] || exit 0
grep -Fq 'position = "auto"' "$flag" || exit 0

# Cycling is what rewrites the rule, and it can only be undone if both displays
# are actually there: switching mirroring off and then failing to switch it back
# on would leave the user extended with nothing saying why. Physical presence
# rather than Hyprland's enabled state, since a display switched off is still
# plugged in and can still be mirrored to once mirroring re-enables it.
if ! omarchy-hw-external-monitors; then
  echo "  no external display attached, leaving mirroring alone"
  exit 0
fi

if [[ -z $(omarchy-hyprland-monitor-laptop) ]]; then
  echo "  no laptop panel to mirror, leaving mirroring alone"
  exit 0
fi

# Keep the rule as it stands so an incomplete cycle can be put back, rather than
# leaving a machine extended that was mirroring when the migration started.
previous=$(cat "$flag")

# Switching mirroring off removes the rule and reloads Hyprland, so by the time
# anything can fail the session is already extended. Putting the file back is
# not enough on its own: without a reload the rule would claim mirroring while
# the displays stay extended, which is the state this is here to avoid.
restore() {
  printf '%s\n' "$previous" >"$flag"

  if hyprctl reload >/dev/null 2>&1; then
    echo "  could not pin the mirror, put the existing rule back"
  else
    echo "  could not pin the mirror, and could not reload to restore it"
    echo "  mirroring is off until the next reload, and the rule is back in $flag"
  fi
  exit 0
}

# --quiet: the user did not ask for this, so a single repair should not stack up
# notifications. Failures still speak up.
omarchy-hyprland-monitor-internal-mirror off --quiet || restore
omarchy-hyprland-monitor-internal-mirror on --quiet || restore

# Only trust it once the new rule is actually on disk and no longer the old one.
[[ -f $flag ]] || restore
if grep -Fq 'position = "auto"' "$flag"; then
  restore
fi

echo "  mirroring now holds the position of the display it mirrors"
