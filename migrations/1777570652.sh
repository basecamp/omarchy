echo "Update interface_ colours for limine 12 (palette index -> RRGGBB)"

if [[ -f /boot/limine.conf ]]; then
  sudo sed -i 's/^interface_branding_color: 2$/interface_branding_colour: 9ece6a/' /boot/limine.conf
  sudo sed -i 's/^interface_branding_color: /interface_branding_colour: /' /boot/limine.conf

  if ! grep -q '^interface_help_colour:' /boot/limine.conf; then
    echo 'interface_help_colour: 9ece6a' | sudo tee -a /boot/limine.conf >/dev/null
  fi

  if ! grep -q '^interface_help_colour_bright:' /boot/limine.conf; then
    echo 'interface_help_colour_bright: 9ece6a' | sudo tee -a /boot/limine.conf >/dev/null
  fi
fi
