echo "Add audio output switching keybinding (SUPER + XF86AudioMute) and command script"

# Create the audio switch command script
SCRIPT_PATH="$HOME/.local/share/omarchy/bin/omarchy-cmd-audio-switch"
if [ ! -f "$SCRIPT_PATH" ]; then
  mkdir -p "$(dirname "$SCRIPT_PATH")"
  cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash

# Switch to the next available audio output
# Preserves mute status across switches

# Get all sink IDs
get_sink_ids() {
    wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -E '^\s*│\s+\*?\s*[0-9]+\.' | sed -E 's/^[^0-9]*([0-9]+)\..*/\1/'
}

# Get current sink ID (marked with *)
get_current_sink() {
    wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep '^\s*│\s*\*' | sed -E 's/^[^0-9]*([0-9]+)\..*/\1/'
}

# Check if current sink is muted
is_muted() {
    local sink_id="$1"
    wpctl get-volume "$sink_id" | grep -q '\[MUTED\]'
}

# Main
sinks=($(get_sink_ids))
[ ${#sinks[@]} -eq 0 ] && exit 1

current=$(get_current_sink)
current_muted=0

# Save mute status if we have a current sink
if [ -n "$current" ]; then
    is_muted "$current" && current_muted=1
    
    # Find current position
    for i in "${!sinks[@]}"; do
        if [ "${sinks[$i]}" = "$current" ]; then
            next_idx=$(( (i + 1) % ${#sinks[@]} ))
            break
        fi
    done
fi

# Default to first sink if no current or not found
next="${sinks[${next_idx:-0}]}"

# Switch and apply mute status
wpctl set-default "$next"
wpctl set-mute "$next" "$current_muted"
EOF
  chmod +x "$SCRIPT_PATH"
  echo "Created audio switch command script"
fi

# Modify the DEFAULT media.conf that comes with Omarchy installation
DEFAULT_MEDIA_CONF="$HOME/.local/share/omarchy/default/hypr/bindings/media.conf"

# Add the audio output switching keybinding if it doesn't exist
if [ -f "$DEFAULT_MEDIA_CONF" ] && ! grep -q "Switch audio output" "$DEFAULT_MEDIA_CONF"; then
  # Add the binding after the playerctl media controls
  sed -i '/XF86AudioPrev.*Previous track/a\
\
# Switch audio output with Super + Mute\
bindld = SUPER, XF86AudioMute, Switch audio output, exec, omarchy-cmd-audio-switch' "$DEFAULT_MEDIA_CONF"
  
  echo "Added audio output switching keybinding to default Omarchy config"
fi

# Also update personal config if it exists (to maintain consistency)
PERSONAL_MEDIA_CONF="$HOME/.config/hypr/bindings/media.conf"
if [ -f "$PERSONAL_MEDIA_CONF" ] && ! grep -q "Switch audio output" "$PERSONAL_MEDIA_CONF"; then
  sed -i '/XF86AudioPrev.*Previous track/a\
\
# Switch audio output with Super + Mute\
bindld = SUPER, XF86AudioMute, Switch audio output, exec, omarchy-cmd-audio-switch' "$PERSONAL_MEDIA_CONF"
  
  echo "Also updated existing personal config for consistency"
fi

# Check if Hyprland is running and reload configuration
if pgrep -x Hyprland >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
  echo "Hyprland configuration reloaded"
fi