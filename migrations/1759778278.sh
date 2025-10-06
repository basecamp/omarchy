echo "Fix random key press/mouse movement on wake"

CONFIG_FILE="$HOME/.config/hypr/hypridle.conf"

# Ensure the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file not found at $CONFIG_FILE. Creating a new one."
    touch "$CONFIG_FILE"
fi

if ! grep -q "key_press_enables_dpms = true" "$CONFIG_FILE"; then
    sed -i '$a key_press_enables_dpms = true' "$CONFIG_FILE"
fi
if ! grep -q "mouse_move_enables_dpms = true" "$CONFIG_FILE"; then
    sed -i '$a mouse_move_enables_dpms = true' "$CONFIG_FILE"
fi

echo "Migration 1758808620: Added DPMS rules to $CONFIG_FILE"
