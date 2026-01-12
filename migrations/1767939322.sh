echo "Add voxtype compositor integration"

VOXTYPE_CONFIG=~/.config/voxtype/config.toml
HYPR_BINDINGS=~/.config/hypr/bindings.conf

# Skip if voxtype is not installed
[[ ! -f "$VOXTYPE_CONFIG" ]] && exit 0

# Add hooks to voxtype config if not present
if ! grep -q "pre_recording_command" "$VOXTYPE_CONFIG"; then
  sed -i '/^type_delay_ms = /a\
\
# Compositor integration hooks for Hyprland\
pre_recording_command = "hyprctl dispatch submap voxtype_recording"\
pre_output_command = "hyprctl dispatch submap voxtype_suppress"\
post_output_command = "hyprctl dispatch submap reset"' "$VOXTYPE_CONFIG"
fi

# Add voxtype bindings to hypr bindings.conf if not present
if [[ -f "$HYPR_BINDINGS" ]] && ! grep -q "voxtype_recording" "$HYPR_BINDINGS"; then
  cat >> "$HYPR_BINDINGS" << 'EOF'

# Voxtype dictation bindings
# Press SUPER+CTRL+X to record, release X to stop (keep modifiers held), ESCAPE to cancel
# Or release a modifier first for toggle mode, then press SUPER+CTRL+X again to stop
bindd = SUPER CTRL, X, Start dictation, exec, voxtype record start

# Voxtype recording submap - active during recording/transcription
submap = voxtype_recording
binddr = SUPER CTRL, X, Stop dictation, exec, voxtype record stop
binddi = , ESCAPE, Cancel dictation, exec, voxtype record cancel; hyprctl dispatch submap reset
submap = reset
EOF
fi
