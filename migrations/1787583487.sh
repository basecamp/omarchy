echo "Replace omazed with native Zed theming"

marker_start="# >>> omazed hook - do not edit >>>"
marker_end="# <<< omazed hook - do not edit <<<"
hook_file="$HOME/.config/omarchy/hooks/theme-set"
hook_dir="$HOME/.config/omarchy/hooks/theme-set.d"
zed_settings="$HOME/.config/zed/settings.json"
was_using_omazed=false

if [[ -f $zed_settings ]] && grep -qE '"theme"[[:space:]]*:[[:space:]]*"Omazed"' "$zed_settings"; then
  was_using_omazed=true
fi

if [[ -f $hook_file ]] && grep -Fq "$marker_start" "$hook_file"; then
  sed -i "/^$marker_start$/,/^$marker_end$/d" "$hook_file"
fi

rm -f "$hook_dir/omazed"
rmdir "$hook_dir" 2>/dev/null || true
rm -f "$HOME/.config/zed/themes/omazed.json"

omarchy-pkg-drop omazed
omarchy-theme-refresh

if [[ $was_using_omazed == true ]]; then
  omarchy-theme-set-zed --select
fi
