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
  [[ -f $desktop ]] || continue
  icon=$(sed -n 's/^Icon=//p' "$desktop" | head -1)
  [[ $icon == "$icons_dir/"* ]] || continue
  [[ -e $icon ]] && continue
  icon_name="${icon##*/}"
  for backup in "$apps_dir"/icons.omarchy-upgrade-to-quattro.*.bak/"$icon_name"; do
    [[ -f $backup ]] || continue
    mkdir -p "$icons_dir"
    cp -f "$backup" "$icon"
    restored=1
    break
  done
done

removed_alacritty=0
if [[ -f $apps_dir/Alacritty.desktop ]] && omarchy-cmd-missing alacritty; then
  rm -f "$apps_dir/Alacritty.desktop"
  removed_alacritty=1
fi

if (( restored || removed_alacritty )) && omarchy-cmd-present update-desktop-database; then
  update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
fi
