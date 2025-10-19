echo "Update UKI to custom named entry"

if command -v limine &>/dev/null && [[ -f /etc/default/limine ]]; then
  if grep -q "^ENABLE_UKI=yes" /etc/default/limine; then
    if ! grep -q "^CUSTOM_UKI_NAME=" /etc/default/limine; then
      sudo sed -i '/^ENABLE_UKI=yes/a CUSTOM_UKI_NAME="omarchy"' /etc/default/limine
    fi

    # Remove the archinstall-created Limine entry
    while IFS= read -r bootnum; do
      sudo efibootmgr -b "$bootnum" -B >/dev/null 2>&1
    done < <(efibootmgr | grep -E "^Boot[0-9]{4}\*? Arch Linux Limine" | sed 's/^Boot\([0-9]\{4\}\).*/\1/')

    sudo limine-update

    uki_file=$(find /boot/EFI/Linux/ -name "omarchy*.efi" -printf "%f\n" 2>/dev/null | head -1)

    if [[ -n "$uki_file" ]]; then
      while IFS= read -r bootnum; do
        sudo efibootmgr -b "$bootnum" -B >/dev/null 2>&1
      done < <(efibootmgr | grep -E "^Boot[0-9]{4}\*? Omarchy" | sed 's/^Boot\([0-9]\{4\}\).*/\1/')

      # Skip EFI entry creation on Apple hardware
      if ! cat /sys/class/dmi/id/bios_vendor 2>/dev/null | grep -qi "Apple"; then
        sudo efibootmgr --create \
          --disk "$(findmnt -n -o SOURCE /boot | sed 's/p\?[0-9]*$//')" \
          --part "$(findmnt -n -o SOURCE /boot | grep -o 'p\?[0-9]*$' | sed 's/^p//')" \
          --label "Omarchy" \
          --loader "\\EFI\\Linux\\$uki_file"
      fi
    fi
  else
    echo "Not using UKI. Not making any changes."
  fi
else
  echo "Boot config is non-standard. Not making any changes."
fi

