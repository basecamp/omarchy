echo "Update hyprland-preview-share-picker config to default to outputs page"

CONFIG_FILE=~/.config/hyprland-preview-share-picker/config.yaml

if [[ -f $CONFIG_FILE ]]; then
  sed -i 's/^default_page: windows$/default_page: outputs/' "$CONFIG_FILE"
fi
