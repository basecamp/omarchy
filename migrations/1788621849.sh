echo "Follow the T1 ambient light sensor for panel and keyboard backlight"

product_name=$(cat "${OMARCHY_DMI_PRODUCT_NAME:-/sys/class/dmi/id/product_name}" 2>/dev/null)
[[ $product_name =~ MacBookPro13,[23]|MacBookPro14,[23] ]] || exit 0

systemctl --user daemon-reload >/dev/null 2>&1 || true

if ! systemctl --user enable omarchy-als-brightness.service >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-als-brightness.service \
    "$wants_dir/omarchy-als-brightness.service"
fi

if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start omarchy-als-brightness.service >/dev/null 2>&1 || true
fi
