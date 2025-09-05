if command -v limine &>/dev/null; then
  # Detect MacBook models that need SPI keyboard modules
  MACBOOK_SPI_MODULES=""
  if [ -f "/sys/class/dmi/id/product_name" ]; then
    PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
    if [[ "$PRODUCT_NAME" =~ MacBook12,1|MacBookPro13,[123]|MacBookPro14,[123] ]]; then
      echo "Detected MacBook with SPI keyboard: $PRODUCT_NAME"
      
      # Ensure applespi driver is available
      if ! modprobe -nq applespi 2>/dev/null && ! modinfo applespi &>/dev/null; then
        if ! pacman -Qi macbook12-spi-driver-dkms &>/dev/null; then
          echo "Installing macbook12-spi-driver-dkms for SPI keyboard support..."
          if command -v yay &>/dev/null; then
            yay -S --noconfirm macbook12-spi-driver-dkms
          elif command -v paru &>/dev/null; then
            paru -S --noconfirm macbook12-spi-driver-dkms
          else
            echo "Warning: AUR helper (yay/paru) not found. Please install macbook12-spi-driver-dkms manually:"
            echo "  yay -S macbook12-spi-driver-dkms"
            echo "WARNING: MacBook SPI keyboard will NOT work at LUKS prompt without manual driver installation"
            
            # Log warning to systemd journal for persistent troubleshooting
            echo "WARNING: MacBook $PRODUCT_NAME detected but AUR helper not available. MacBook SPI driver not installed. Internal keyboard will not work at LUKS prompt. Manual installation required: yay -S macbook12-spi-driver-dkms" | systemd-cat -t omarchy -p warning
          fi
        fi
      fi
      
      MACBOOK_SPI_MODULES="applespi intel_lpss_pci spi_pxa2xx_platform"
      
      # Log MacBook detection to systemd journal (boot log)
      echo "MacBook SPI keyboard support configured for $PRODUCT_NAME" | systemd-cat -t macbook -p info
    fi
  fi

  # Create mkinitcpio config with conditional MacBook modules
  sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<EOF >/dev/null
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
$([ -n "$MACBOOK_SPI_MODULES" ] && echo "MODULES=($MACBOOK_SPI_MODULES)")
EOF

  [[ -f /boot/EFI/limine/limine.conf ]] || [[ -f /boot/EFI/BOOT/limine.conf ]] && EFI=true

  # Conf location is different between EFI and BIOS
  if [[ -n "$EFI" ]]; then
    # Check USB location first, then regular EFI location
    if [[ -f /boot/EFI/BOOT/limine.conf ]]; then
      limine_config="/boot/EFI/BOOT/limine.conf"
    else
      limine_config="/boot/EFI/limine/limine.conf"
    fi
  else
    limine_config="/boot/limine/limine.conf"
  fi

  # Double-check and exit if we don't have a config file for some reason
  if [[ ! -f $limine_config ]]; then
    echo "Error: Limine config not found at $limine_config" >&2
    exit 1
  fi

  CMDLINE=$(grep "^[[:space:]]*cmdline:" "$limine_config" | head -1 | sed 's/^[[:space:]]*cmdline:[[:space:]]*//')

  sudo tee /etc/default/limine <<EOF >/dev/null
TARGET_OS_NAME="Omarchy"

ESP_PATH="/boot"

KERNEL_CMDLINE[default]="$CMDLINE"
KERNEL_CMDLINE[default]+="quiet splash"

ENABLE_UKI=yes

ENABLE_LIMINE_FALLBACK=yes

# Find and add other bootloaders
FIND_BOOTLOADERS=yes

BOOT_ORDER="*, *fallback, Snapshots"

MAX_SNAPSHOT_ENTRIES=5

SNAPSHOT_FORMAT_CHOICE=5
EOF

  # UKI and EFI fallback are EFI only
  if [[ -z $EFI ]]; then
    sudo sed -i '/^ENABLE_UKI=/d; /^ENABLE_LIMINE_FALLBACK=/d' /etc/default/limine
  fi

  # We overwrite the whole thing knowing the limine-update will add the entries for us
  sudo tee /boot/limine.conf <<EOF >/dev/null
### Read more at config document: https://github.com/limine-bootloader/limine/blob/trunk/CONFIG.md
#timeout: 3
default_entry: 2
interface_branding: Omarchy Bootloader
interface_branding_color: 2
hash_mismatch_panic: no

term_background: 1a1b26
backdrop: 1a1b26

# Terminal colors (Tokyo Night palette)
term_palette: 15161e;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;a9b1d6
term_palette_bright: 414868;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;c0caf5

# Text colors
term_foreground: c0caf5
term_foreground_bright: c0caf5
term_background_bright: 24283b
 
EOF

  sudo pacman -S --noconfirm --needed limine-snapper-sync limine-mkinitcpio-hook
  
  # Rebuild initramfs if MacBook modules were added
  if [ -n "$MACBOOK_SPI_MODULES" ]; then
    echo "Rebuilding initramfs for MacBook SPI keyboard support..."
    sudo mkinitcpio -P
    echo "MacBook SPI keyboard support integrated successfully" | tee >(systemd-cat -t macbook -p info)
  elif [ -f "/sys/class/dmi/id/product_name" ] && [[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" =~ MacBook12,1|MacBookPro13,[23]|MacBookPro14,[23] ]]; then
    # MacBook was detected but modules weren't set (driver installation failed)
    echo "WARNING: MacBook detected but SPI keyboard support could not be configured. Internal keyboard may not work during LUKS encryption prompt" | tee >(systemd-cat -t macbook -p warning)
  fi
  
  sudo limine-update

  # Match Snapper configs if not installing from the ISO
  if [[ -z ${OMARCHY_CHROOT_INSTALL:-} ]]; then
    if ! sudo snapper list-configs 2>/dev/null | grep -q "root"; then
      sudo snapper -c root create-config /
    fi

    if ! sudo snapper list-configs 2>/dev/null | grep -q "home"; then
      sudo snapper -c home create-config /home
    fi
  fi

  # Tweak default Snapper configs
  sudo sed -i 's/^TIMELINE_CREATE="yes"/TIMELINE_CREATE="no"/' /etc/snapper/configs/{root,home}
  sudo sed -i 's/^NUMBER_LIMIT="50"/NUMBER_LIMIT="5"/' /etc/snapper/configs/{root,home}
  sudo sed -i 's/^NUMBER_LIMIT_IMPORTANT="10"/NUMBER_LIMIT_IMPORTANT="5"/' /etc/snapper/configs/{root,home}

  chrootable_systemctl_enable limine-snapper-sync.service
fi

# Add UKI entry to UEFI machines to skip bootloader showing on normal boot
if [[ -n $EFI ]] && efibootmgr &>/dev/null && ! efibootmgr | grep -q Omarchy &&
  ! cat /sys/class/dmi/id/bios_vendor 2>/dev/null | grep -qi "American Megatrends"; then
  sudo efibootmgr --create \
    --disk "$(findmnt -n -o SOURCE /boot | sed 's/p\?[0-9]*$//')" \
    --part "$(findmnt -n -o SOURCE /boot | grep -o 'p\?[0-9]*$' | sed 's/^p//')" \
    --label "Omarchy" \
    --loader "\\EFI\\Linux\\$(cat /etc/machine-id)_linux.efi"
fi
