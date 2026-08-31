echo "Add New File and Copy Path actions to Nautilus"

extensions_dir="$HOME/.local/share/nautilus-python/extensions"
mkdir -p "$extensions_dir"
cp "$OMARCHY_PATH/default/nautilus-python/extensions/file-actions.py" "$extensions_dir/"
