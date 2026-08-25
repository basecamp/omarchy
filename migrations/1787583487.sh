echo "Replace omazed with native Zed theming"

marker_start="# >>> omazed hook - do not edit >>>"
marker_end="# <<< omazed hook - do not edit <<<"
hook_file="$HOME/.config/omarchy/hooks/theme-set"
hook_dir="$HOME/.config/omarchy/hooks/theme-set.d"

if [[ -f $hook_file ]] && awk -v start="$marker_start" -v end="$marker_end" '
  $0 == start { found_start = 1 }
  found_start && $0 == end { found_end = 1; exit }
  END { exit !(found_start && found_end) }
' "$hook_file"; then
  sed -i --follow-symlinks "/^$marker_start$/,/^$marker_end$/d" "$hook_file"
fi

rm -f "$hook_dir/omazed"
rmdir "$hook_dir" 2>/dev/null || true

omarchy-pkg-drop omazed
omarchy-theme-refresh
omarchy-theme-set-zed --migrate

rm -f "$HOME/.config/zed/themes/omazed.json"
rm -f "$HOME/.local/share/omazed/initialized"
rmdir "$HOME/.local/share/omazed" 2>/dev/null || true
