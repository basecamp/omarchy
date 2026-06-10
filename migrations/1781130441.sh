echo "Create waybar presets user directory with README"

PRESETS_USER="$HOME/.config/omarchy/waybar-presets"
mkdir -p "$PRESETS_USER"

if [[ ! -f $PRESETS_USER/README.md ]]; then
  cat > "$PRESETS_USER/README.md" << 'EOF'
# Waybar Layout Presets

Add custom presets here. Each preset is a directory containing:

- `config.jsonc` — Waybar module layout
- `style.css` — Waybar CSS styling

Presets in this directory override shipped presets with the same name.
For default presets, see: ~/.local/share/omarchy/default/waybar/waybar-presets/

Example structure:

  waybar-presets/my-preset/
    ├── config.jsonc
    └── style.css

Use the Omarchy menu to switch: Super+Ctrl+Space → Style → Waybar → Layout.
Or from the command line: omarchy waybar set <preset-name>.
EOF
fi
