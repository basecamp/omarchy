#!/usr/bin/env bash

if ! command -v plymouth &>/dev/null; then
  yay -S --noconfirm --needed plymouth

  # Skip if plymouth already exists for some reason
  # Backup original mkinitcpio.conf just in case
  backup_timestamp=$(date +"%Y%m%d%H%M%S")
  sudo cp /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak.${backup_timestamp}"

  # Add plymouth to HOOKS array after 'base udev' or 'base systemd'
  if grep "^HOOKS=" /etc/mkinitcpio.conf | grep -q "base systemd"; then
    sudo sed -i '/^HOOKS=/s/base systemd/base systemd plymouth/' /etc/mkinitcpio.conf
  elif grep "^HOOKS=" /etc/mkinitcpio.conf | grep -q "base udev"; then
    sudo sed -i '/^HOOKS=/s/base udev/base udev plymouth/' /etc/mkinitcpio.conf
  else
    echo "Couldn't add the Plymouth hook"
  fi

  # Regenerate initramfs
  sudo mkinitcpio -P

  # Add kernel parameters for Plymouth (systemd-boot only)
  if [ -d "/boot/loader/entries" ]; then
    echo "Detected systemd-boot"

    for entry in /boot/loader/entries/*.conf; do
      if [ -f "$entry" ]; then
        # Skip fallback entries
        if [[ "$(basename "$entry")" == *"fallback"* ]]; then
          echo "Skipped: $(basename "$entry") (fallback entry)"
          continue
        fi

        # Skip if splash it already present for some reason
        if ! grep -q "splash" "$entry"; then
          sudo sed -i '/^options/ s/$/ splash/' "$entry"
        else
          echo "Skipped: $(basename "$entry") (splash already present)"
        fi
      fi
    done
  elif [ -f "/etc/default/grub" ]; then
    echo "Detected grub"
    # Backup GRUB config before modifying
    backup_timestamp=$(date +"%Y%m%d%H%M%S")
    sudo cp /etc/default/grub "/etc/default/grub.bak.${backup_timestamp}"

    # Check if splash is already in GRUB_CMDLINE_LINUX_DEFAULT
    if ! grep -q "GRUB_CMDLINE_LINUX_DEFAULT.*splash" /etc/default/grub; then
      # Get current GRUB_CMDLINE_LINUX_DEFAULT value
      current_cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | cut -d'"' -f2)

      # Add splash if not present
      new_cmdline="$current_cmdline"
      if [[ ! "$current_cmdline" =~ splash ]]; then
        new_cmdline="$new_cmdline splash"
      fi

      # Trim any leading/trailing spaces
      new_cmdline=$(echo "$new_cmdline" | xargs)

      sudo sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"/" /etc/default/grub

      # Regenerate grub config
      sudo grub-mkconfig -o /boot/grub/grub.cfg
    else
      echo "GRUB already configured with splash kernel parameters"
    fi
  elif [ -d "/etc/cmdline.d" ]; then
    echo "Detected a UKI setup"
    # Relying on mkinitcpio to assemble a UKI
    # https://wiki.archlinux.org/title/Unified_kernel_image
    if ! grep -q splash /etc/cmdline.d/*.conf; then
        # Need splash, create the omarchy file
        echo "splash" | sudo tee -a /etc/cmdline.d/omarchy.conf
    fi
  elif [ -f "/etc/kernel/cmdline" ]; then
    # Alternate UKI kernel cmdline location
    echo "Detected a UKI setup"

    # Backup kernel cmdline config before modifying
    backup_timestamp=$(date +"%Y%m%d%H%M%S")
    sudo cp /etc/kernel/cmdline "/etc/kernel/cmdline.bak.${backup_timestamp}"

    current_cmdline=$(cat /etc/kernel/cmdline)

    # Add splash if not present
    new_cmdline="$current_cmdline"
    if [[ ! "$current_cmdline" =~ splash ]]; then
        new_cmdline="$new_cmdline splash"
    fi

    # Trim any leading/trailing spaces
    new_cmdline=$(echo "$new_cmdline" | xargs)

    # Write new file
    echo $new_cmdline | sudo tee /etc/kernel/cmdline
  else
    echo ""
    echo "Neither systemd-boot nor GRUB detected. Please manually add these kernel parameters:"
    echo "  - splash (to see the graphical splash screen)"
    echo ""
  fi

  # Copy and set the Plymouth theme
  sudo cp -r "$HOME/.local/share/omarchy/default/plymouth" /usr/share/plymouth/themes/omarchy/

  sudo plymouth-set-default-theme -R omarchy

  # Set up simple Plymouth transition with auto-login
  bash "$HOME/.local/share/omarchy/install/simple-plymouth-transition.sh"
fi
