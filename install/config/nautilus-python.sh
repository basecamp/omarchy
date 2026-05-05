EXTENSIONS_DIR="$HOME/.local/share/nautilus-python/extensions"

mkdir -p "$EXTENSIONS_DIR"
cp "$OMARCHY_PATH/default/nautilus-python/extensions/localsend.py" "$EXTENSIONS_DIR/"
cp "$OMARCHY_PATH/default/nautilus-python/extensions/copy_path.py" "$EXTENSIONS_DIR/"

