echo "Enable live Omarchy theme updates in Nautilus"

extensions_dir="$HOME/.local/share/nautilus-python/extensions"
extension_source="$OMARCHY_PATH/default/nautilus-python/extensions/omarchy_theme.py"
extension_target="$extensions_dir/omarchy_theme.py"

if [[ -f $extension_target ]] && cmp -s "$extension_source" "$extension_target"; then
  exit 0
fi

if [[ -e $extension_target || -L $extension_target ]]; then
  echo "Keeping existing Nautilus extension at $extension_target"
  exit 0
fi

mkdir -p "$extensions_dir"
cp "$extension_source" "$extension_target"
omarchy-theme-refresh || true
