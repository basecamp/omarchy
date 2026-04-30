echo "Update interface_branding_color for limine 12 (palette index -> RRGGBB)"

if [[ -f /boot/limine.conf ]]; then
  sudo sed -i 's/^interface_branding_color: 2$/interface_branding_color: 9ece6a/' /boot/limine.conf
fi
