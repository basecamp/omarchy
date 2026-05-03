echo "Update interface_ colors for limine 12 (palette index -> RRGGBB)"

if [[ -f /boot/limine.conf ]]; then
  sudo sed -i -E 's/^interface_branding_colou?r: 2$/interface_branding_color: 9ece6a/' /boot/limine.conf
  sudo sed -i 's/^interface_branding_colour: /interface_branding_color: /' /boot/limine.conf

  sudo sed -i -E '/^interface_help_colou?r(_bright)?:/d' /boot/limine.conf
  sudo sed -i '/^interface_branding_color:/a interface_help_color_bright: 9ece6a' /boot/limine.conf
  sudo sed -i '/^interface_branding_color:/a interface_help_color: 9ece6a' /boot/limine.conf
fi
