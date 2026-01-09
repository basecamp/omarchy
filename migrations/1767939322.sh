echo "Add voxtype modifier suppression hooks"

CONFIG_FILE=~/.config/voxtype/config.toml

# Only proceed if voxtype config exists
[[ ! -f "$CONFIG_FILE" ]] && exit 0

# Add pre_output_command and post_output_command if not present
if ! grep -q "pre_output_command" "$CONFIG_FILE"; then
  sed -i '/^type_delay_ms = /a\
\
# Modifier key suppression for Hyprland\
# Prevents held modifier keys from interfering with transcription output\
# See: https://github.com/basecamp/omarchy/issues/4159\
pre_output_command = "hyprctl dispatch submap voxtype_suppress"\
post_output_command = "hyprctl dispatch submap reset"' "$CONFIG_FILE"
fi
