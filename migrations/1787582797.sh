echo "Select share regions in output relative coordinates"

config="$HOME/.config/hyprland-preview-share-picker/config.yaml"

[[ -f $config ]] || exit 0
grep -q "%o@%x,%y,%w,%h" "$config" || exit 0

sed -i "s|%o@%x,%y,%w,%h|%o@%X,%Y,%W,%H|" "$config"
