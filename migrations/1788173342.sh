echo "Restore app-menu icons the Quattro upgrade moved out from under surviving launchers"

# The upgrade used to park every stock PNG under
# ~/.local/share/applications/icons.omarchy-upgrade-to-quattro.*.bak before
# leftover custom .desktop files were rewritten. Those launchers still name
# the old absolute Icon= path, so the Apps menu shows a generic icon and the
# shell logs QQuickImage "Cannot open" on every open. The same pass also
# installed Alacritty.desktop even when alacritty was not on PATH.

apps_dir="$HOME/.local/share/applications"
icons_dir="$apps_dir/icons"
restored=0

for desktop in "$apps_dir"/*.desktop; do
  # An unreadable launcher makes sed exit non-zero, and a repair migration that
  # dies on one stray file now aborts the whole Quattro upgrade.
  [[ -f $desktop && -r $desktop ]] || continue
  icon=$(sed -n '/^Icon=/ { s/^Icon=//; p; q; }' "$desktop")
  icon_name="${icon##*/}"
  [[ $icon == "$icons_dir/$icon_name" ]] || continue
  # A dangling symlink is not -e, and GNU cp then refuses to write through it
  # and exits 1. Under bash -euo pipefail that aborts the rest of the loop.
  [[ -e $icon || -L $icon ]] && continue
  # Last match wins: a home that survived two upgrades has one backup per run,
  # and the newest holds the icon the launcher was last drawn with.
  backup=""
  for candidate in "$apps_dir"/icons.omarchy-upgrade-to-quattro.*.bak/"$icon_name"; do
    [[ -f $candidate ]] || continue
    backup="$candidate"
  done
  [[ -n $backup ]] || continue
  # icons/ is itself a dangling symlink on some homes, and mkdir -p exits 1 on
  # one rather than following it.
  mkdir -p "$icons_dir" 2>/dev/null || continue
  cp -f "$backup" "$icon"
  restored=1
done

removed_alacritty=0
# The upgrade-installed ghost carries TryExec=alacritty. A hand-written
# Alacritty.desktop that launches a Flatpak, wrapper, or SSH session does not.
if [[ -f $apps_dir/Alacritty.desktop ]] && omarchy-cmd-missing alacritty &&
  grep -qxF 'TryExec=alacritty' "$apps_dir/Alacritty.desktop"; then
  rm -f "$apps_dir/Alacritty.desktop"
  removed_alacritty=1
fi

if (( restored || removed_alacritty )) && omarchy-cmd-present update-desktop-database; then
  update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
fi
