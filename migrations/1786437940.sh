echo "Refresh Nautilus Transcode context menu"

extensions_dir="$HOME/.local/share/nautilus-python/extensions"

mkdir -p "$extensions_dir"
cp "$OMARCHY_PATH/default/nautilus-python/extensions/transcode.py" "$extensions_dir/"
