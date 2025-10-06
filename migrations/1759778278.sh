echo "Fix random key press/mouse movement on wake in Hyprland"

CONFIG_DIR="$HOME/.config/hypr"
HYPRLAND_CONFIG="$CONFIG_DIR/hyprland.conf"
MISC_CONFIG="$CONFIG_DIR/misc.conf"

# Ensure configuration directory exists
mkdir -p "$CONFIG_DIR"

# Create or modify misc.conf
if [ ! -f "$MISC_CONFIG" ]; then
    echo "Creating $MISC_CONFIG with misc section..."
    cat > "$MISC_CONFIG" <<'EOF'
misc {
    key_press_enables_dpms = true
    mouse_move_enables_dpms = true
}
EOF
else
    # Only insert if not already present
    if ! grep -q "key_press_enables_dpms" "$MISC_CONFIG" && ! grep -q "mouse_move_enables_dpms" "$MISC_CONFIG"; then
        echo "Adding key_press_enables_dpms and mouse_move_enables_dpms to misc section in $MISC_CONFIG..."
        awk '
            /misc[[:space:]]*{/ {
                in_misc=1
                print
                next
            }
            in_misc && /\}/ {
                print "    key_press_enables_dpms = true"
                print "    mouse_move_enables_dpms = true"
                in_misc=0
            }
            { print }
            in_misc { next }
            END {
                if (in_misc) {
                    print "    key_press_enables_dpms = true"
                    print "    mouse_move_enables_dpms = true"
                    print "}"
                } else if (!seen_misc) {
                    print "\nmisc {"
                    print "    key_press_enables_dpms = true"
                    print "    mouse_move_enables_dpms = true"
                    print "}"
                }
            }
            BEGIN { seen_misc=0 }
            /misc[[:space:]]*{/ { seen_misc=1 }
        ' "$MISC_CONFIG" > "${MISC_CONFIG}.tmp" && mv "${MISC_CONFIG}.tmp" "$MISC_CONFIG"
    else
        echo "DPMS settings already exist in $MISC_CONFIG"
    fi
fi

# Ensure hyprland.conf sources misc.conf
if [ ! -f "$HYPRLAND_CONFIG" ]; then
    echo "Creating $HYPRLAND_CONFIG with source directive..."
    cat > "$HYPRLAND_CONFIG" <<'EOF'
source = ~/.config/hypr/misc.conf
EOF
else
    if ! grep -q "source[[:space:]]*=[[:space:]]*~/.config/hypr/misc.conf" "$HYPRLAND_CONFIG"; then
        echo "Adding source directive to $HYPRLAND_CONFIG..."
        echo "source = ~/.config/hypr/misc.conf" >> "$HYPRLAND_CONFIG"
    else
        echo "Source directive for misc.conf already exists in $HYPRLAND_CONFIG"
    fi
fi
