if command -v limine &>/dev/null; then
  sudo pacman -S --noconfirm --needed limine-snapper-sync limine-mkinitcpio-hook

  sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<EOF >/dev/null
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
EOF
  sudo tee /etc/mkinitcpio.conf.d/thunderbolt_module.conf <<EOF >/dev/null
MODULES+=(thunderbolt)
EOF

  # Detect boot mode
  [[ -d /sys/firmware/efi ]] && EFI=true

  # Find config location
  if [[ -f /boot/EFI/arch-limine/limine.conf ]]; then
    limine_config="/boot/EFI/arch-limine/limine.conf"
  elif [[ -f /boot/EFI/BOOT/limine.conf ]]; then
    limine_config="/boot/EFI/BOOT/limine.conf"
  elif [[ -f /boot/EFI/limine/limine.conf ]]; then
    limine_config="/boot/EFI/limine/limine.conf"
  elif [[ -f /boot/limine/limine.conf ]]; then
    limine_config="/boot/limine/limine.conf"
  elif [[ -f /boot/limine.conf ]]; then
    limine_config="/boot/limine.conf"
  else
    echo "Error: Limine config not found" >&2
    exit 1
  fi

  CMDLINE=$(grep "^[[:space:]]*cmdline:" "$limine_config" | head -1 | sed 's/^[[:space:]]*cmdline:[[:space:]]*//')

  sudo cp $OMARCHY_PATH/default/limine/default.conf /etc/default/limine
  sudo sed -i "s|@@CMDLINE@@|$CMDLINE|g" /etc/default/limine

  # UKI and EFI fallback are EFI only
  if [[ -z $EFI ]]; then
    sudo sed -i '/^ENABLE_UKI=/d; /^ENABLE_LIMINE_FALLBACK=/d' /etc/default/limine
    
    # Check if Libreboot GRUB payload is being used
    # Libreboot GRUB looks for /boot/grub/i386-coreboot/ files
    # We detect this by checking if Libreboot was detected and if GRUB errors mention i386-coreboot
    LIBREBOOT_GRUB=false
    
    # Check for detection marker file (persisted from preflight phase)
    # This works even if environment variables don't persist in chroot
    if [[ -f /tmp/omarchy-libreboot-detected-flag ]] || [[ -n "${OMARCHY_LIBREBOOT_DETECTED:-}" ]]; then
      # Check if system is likely using Libreboot GRUB payload
      # (Libreboot can use GRUB or SeaBIOS payload - we need GRUB for GRUB payload)
      if dmesg 2>/dev/null | grep -qiE "libreboot.*grub|grub.*libreboot|i386-coreboot" || \
         [[ -f /boot/grub/i386-coreboot/ ]] 2>/dev/null; then
        LIBREBOOT_GRUB=true
        echo "Libreboot GRUB payload detected - will install GRUB for compatibility"
      else
        # Assume Libreboot might use GRUB payload - install GRUB anyway for safety
        LIBREBOOT_GRUB=true
        echo "Libreboot detected - installing GRUB for Libreboot GRUB payload compatibility"
      fi
    fi
    
    # Install Limine in BIOS/MBR mode for non-EFI systems (Libreboot/Coreboot without EFI payload)
    echo "EFI not detected - installing Limine in BIOS/MBR mode..."
    
    # Find the root disk device
    # Try to find from /boot mount point first, fallback to root filesystem
    boot_source=$(findmnt -n -o SOURCE /boot 2>/dev/null || findmnt -n -o SOURCE / 2>/dev/null)
    if [[ -z "$boot_source" ]]; then
      echo "Warning: Could not determine boot device. Skipping BIOS bootloader installation." >&2
    else
      # Extract disk device (remove partition number)
      root_disk=$(echo "$boot_source" | sed 's/p\?[0-9]*$//')
      
      # Verify the disk exists
      if [[ ! -b "$root_disk" ]]; then
        echo "Warning: Disk device $root_disk not found. Skipping BIOS bootloader installation." >&2
      else
        # Check partition table type (use sudo if needed)
        partition_table=$(sudo parted -s "$root_disk" print 2>/dev/null | grep "Partition Table:" | awk '{print $3}' || echo "")
        
        if [[ "$partition_table" == "gpt" ]]; then
          # GPT disk - check if BIOS boot partition exists
          bios_boot_part=$(sudo parted -s "$root_disk" print 2>/dev/null | grep -i "bios_grub\|bios boot" | head -1 || echo "")
          
          if [[ -z "$bios_boot_part" ]]; then
            echo "GPT disk detected but no BIOS boot partition found."
            echo "Note: BIOS boot partition (1 MiB, type ef02) should be created during initial partitioning."
            echo "Attempting to install Limine anyway - it may work if space is available in the first 1MB..."
            echo "If boot fails, you may need to recreate partitions with a BIOS boot partition."
          else
            echo "GPT disk with BIOS boot partition detected - good!"
          fi
        elif [[ "$partition_table" == "msdos" ]] || [[ "$partition_table" == "mbr" ]]; then
          # MBR disk - no special partition needed (bootloader uses MBR gap)
          echo "MBR disk detected - no BIOS boot partition needed, installing Limine to MBR..."
        else
          echo "Warning: Unknown partition table type: $partition_table" >&2
        fi
        
        # If Libreboot GRUB payload is detected, skip Limine and use GRUB only
        # Libreboot GRUB payload runs first, so Limine in MBR would never be reached
        if [[ "$LIBREBOOT_GRUB" == "true" ]]; then
          # Install GRUB with i386-pc target (standard GRUB modules)
          # Key discovery: i386-pc modules work with Libreboot GRUB payload!
          # Missing filesystem modules (sfs, reiserfs, etc.) are skipped and not needed for Btrfs/LUKS
          echo "=========================================="
          echo "Installing GRUB for Libreboot GRUB payload compatibility..."
          echo "=========================================="
          echo ""
          echo "NOTE: Installing GRUB with i386-pc modules (standard GRUB)."
          echo "Libreboot GRUB payload can use i386-pc modules - no additional modules needed!"
          echo ""
          echo "Pausing for 10 seconds to allow screenshot..."
          echo ""
          
          # Pause to allow user to see the message and take a screenshot
          # Can be skipped by setting OMARCHY_SKIP_DETECTION_PAUSE=1
          if [[ -z "${OMARCHY_SKIP_DETECTION_PAUSE:-}" ]]; then
            sleep 10
          fi
          
          # Check if GRUB is installed, install if needed
          if ! command -v grub-install &>/dev/null; then
            echo "Warning: grub-install not found. Installing GRUB package..." >&2
            sudo pacman -S --noconfirm --needed grub 2>&1 || {
              echo "Error: Failed to install GRUB. Libreboot GRUB may not be able to boot this system." >&2
              exit 1
            }
          fi
          
          # Install GRUB with i386-pc target (standard modules work with Libreboot GRUB payload)
          sudo grub-install --target=i386-pc --recheck --force "$root_disk" 2>&1 || {
            echo "Warning: GRUB installation for Libreboot failed. You may need to configure Libreboot GRUB manually." >&2
          }
          
          # Configure GRUB for encrypted root before generating config
          # This ensures cryptdevice parameter is included
          if [[ -f /etc/default/grub ]]; then
            # Enable cryptodisk support
            if ! grep -q "^GRUB_ENABLE_CRYPTODISK=y" /etc/default/grub; then
              sudo sed -i 's/^#GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
              echo "GRUB_ENABLE_CRYPTODISK=y" | sudo tee -a /etc/default/grub >/dev/null
            fi
          else
            # Create /etc/default/grub if it doesn't exist
            sudo mkdir -p /etc/default
            echo "GRUB_DEFAULT=0" | sudo tee /etc/default/grub >/dev/null
            echo "GRUB_TIMEOUT=5" | sudo tee -a /etc/default/grub >/dev/null
            echo "GRUB_ENABLE_CRYPTODISK=y" | sudo tee -a /etc/default/grub >/dev/null
          fi
          
          # Get correct UUIDs BEFORE generating GRUB config
          # This ensures we use the installed system's UUIDs, not the live ISO's
          installed_luks_uuid=""
          installed_btrfs_uuid=""
          luks_partition=""
          
          # Find LUKS partition UUID from the installed disk
          # Try all possible partition numbers (p1-p9, 1-9)
          for part_suffix in "p2" "p3" "p4" "2" "3" "4"; do
            part_device="${root_disk}${part_suffix}"
            if [[ -b "$part_device" ]]; then
              # Use sudo for blkid if needed
              part_type=$(sudo blkid -s TYPE -o value "$part_device" 2>/dev/null || blkid -s TYPE -o value "$part_device" 2>/dev/null || echo "")
              if [[ "$part_type" == "crypto_LUKS" ]]; then
                installed_luks_uuid=$(sudo blkid -s UUID -o value "$part_device" 2>/dev/null || blkid -s UUID -o value "$part_device" 2>/dev/null || echo "")
                if [[ -n "$installed_luks_uuid" ]]; then
                  luks_partition="$part_device"
                  echo "Found LUKS partition: $luks_partition (UUID: $installed_luks_uuid)" >&2
                  break
                fi
              fi
            fi
          done
          
          # If still not found, scan all partitions on the disk
          if [[ -z "$installed_luks_uuid" ]]; then
            echo "Scanning all partitions for LUKS..." >&2
            for part in $(lsblk -n -o NAME "$root_disk" 2>/dev/null | grep -E "^${root_disk##*/}p?[0-9]+$" || true); do
              part_device="/dev/$part"
              if [[ -b "$part_device" ]]; then
                part_type=$(sudo blkid -s TYPE -o value "$part_device" 2>/dev/null || blkid -s TYPE -o value "$part_device" 2>/dev/null || echo "")
                if [[ "$part_type" == "crypto_LUKS" ]]; then
                  installed_luks_uuid=$(sudo blkid -s UUID -o value "$part_device" 2>/dev/null || blkid -s UUID -o value "$part_device" 2>/dev/null || echo "")
                  if [[ -n "$installed_luks_uuid" ]]; then
                    luks_partition="$part_device"
                    echo "Found LUKS partition: $luks_partition (UUID: $installed_luks_uuid)" >&2
                    break
                  fi
                fi
              fi
            done
          fi
          
          # If LUKS UUID found, try to get Btrfs UUID
          # Method 1: Try to get from already-mounted filesystem (if chroot is mounted)
          if [[ -n "$installed_luks_uuid" ]] && [[ -n "$luks_partition" ]]; then
            # Check if root filesystem is already mounted (common in chroot)
            if mountpoint -q / 2>/dev/null; then
              # Get UUID from mounted root filesystem
              root_source=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
              if [[ -n "$root_source" ]]; then
                # Try findmnt first (works with mounted filesystems)
                installed_btrfs_uuid=$(findmnt -n -o UUID / 2>/dev/null || echo "")
                # If that fails, try blkid on the source
                if [[ -z "$installed_btrfs_uuid" ]] && [[ -n "$root_source" ]]; then
                  installed_btrfs_uuid=$(sudo blkid -s UUID -o value "$root_source" 2>/dev/null || blkid -s UUID -o value "$root_source" 2>/dev/null || echo "")
                fi
                if [[ -n "$installed_btrfs_uuid" ]]; then
                  echo "Found Btrfs UUID from mounted filesystem: $installed_btrfs_uuid" >&2
                fi
              fi
            fi
            
            # Method 2: If not mounted, try to open LUKS temporarily (may require password)
            if [[ -z "$installed_btrfs_uuid" ]]; then
              temp_mapper="omarchy-temp-$$"
              # Try to open LUKS (will fail silently if password required)
              if cryptsetup luksOpen "$luks_partition" "$temp_mapper" 2>/dev/null; then
                installed_btrfs_uuid=$(blkid -s UUID -o value "/dev/mapper/$temp_mapper" 2>/dev/null || echo "")
                cryptsetup luksClose "$temp_mapper" 2>/dev/null || true
              fi
            fi
            
            # Method 3: Try to get from /etc/fstab in installed system
            if [[ -z "$installed_btrfs_uuid" ]] && [[ -f /etc/fstab ]]; then
              fstab_uuid=$(grep -E "^UUID=|^/dev/mapper" /etc/fstab | grep -E "subvol=@|/ " | head -1 | grep -o "UUID=[^ ]*" | sed 's/UUID=//' || echo "")
              if [[ -n "$fstab_uuid" ]]; then
                installed_btrfs_uuid="$fstab_uuid"
              fi
            fi
          fi
          
          # Generate GRUB config (needed for when modules are available)
          if command -v grub-mkconfig &>/dev/null; then
            sudo grub-mkconfig -o /boot/grub/grub.cfg 2>&1 || {
              echo "Warning: GRUB config generation failed." >&2
            }
            
            # CRITICAL: Verify and fix UUIDs after grub-mkconfig
            # grub-mkconfig might detect the live ISO's UUID instead of installed system's UUID
            if [[ -f /boot/grub/grub.cfg ]]; then
              # Get current UUID from GRUB config
              current_root_uuid=$(grep -o "root=UUID=[^ ]*" /boot/grub/grub.cfg | head -1 | sed 's/root=UUID=//' || echo "")
              
              # If we have the correct Btrfs UUID, verify and fix
              if [[ -n "$installed_btrfs_uuid" ]] && [[ -n "$current_root_uuid" ]]; then
                if [[ "$current_root_uuid" != "$installed_btrfs_uuid" ]]; then
                  echo "Warning: GRUB config has wrong UUID (likely from USB stick). Fixing..." >&2
                  echo "  Found UUID: $current_root_uuid" >&2
                  echo "  Correct UUID: $installed_btrfs_uuid" >&2
                  
                  # Replace wrong UUID with correct one
                  sudo sed -i "s|root=UUID=$current_root_uuid|root=UUID=$installed_btrfs_uuid|g" /boot/grub/grub.cfg
                  echo "Fixed root UUID in GRUB config" >&2
                fi
              elif [[ -z "$installed_btrfs_uuid" ]]; then
                # If we couldn't get Btrfs UUID, try to detect if current UUID is from USB
                # Check if current UUID matches any mounted USB device
                usb_uuid_found=false
                for mount_point in $(findmnt -n -o TARGET 2>/dev/null | grep -E "^/run/media|^/media|^/mnt" || true); do
                  mount_uuid=$(findmnt -n -o UUID "$mount_point" 2>/dev/null || echo "")
                  if [[ "$mount_uuid" == "$current_root_uuid" ]]; then
                    usb_uuid_found=true
                    echo "Warning: GRUB config UUID matches USB device at $mount_point!" >&2
                    break
                  fi
                done
                
                if [[ "$usb_uuid_found" == "true" ]]; then
                  echo "ERROR: GRUB config has USB UUID instead of installed disk UUID!" >&2
                  echo "  This will cause boot failure. Attempting to fix..." >&2
                  echo "  Current (wrong) UUID: $current_root_uuid" >&2
                  echo "  Attempting to get correct UUID from installed disk..." >&2
                  
                  # Last resort: Try to get UUID from /etc/fstab or mount info
                  # If root is mounted, get its UUID
                  if mountpoint -q / 2>/dev/null; then
                    root_source=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
                    if [[ -n "$root_source" ]]; then
                      correct_uuid=$(blkid -s UUID -o value "$root_source" 2>/dev/null || echo "")
                      if [[ -n "$correct_uuid" ]] && [[ "$correct_uuid" != "$current_root_uuid" ]]; then
                        echo "  Found correct UUID: $correct_uuid" >&2
                        sudo sed -i "s|root=UUID=$current_root_uuid|root=UUID=$correct_uuid|g" /boot/grub/grub.cfg
                        echo "Fixed root UUID in GRUB config" >&2
                      fi
                    fi
                  fi
                else
                  echo "Warning: Could not determine installed system's Btrfs UUID for verification." >&2
                  echo "  GRUB config may have wrong UUID from USB stick." >&2
                  echo "  Current UUID in config: $current_root_uuid" >&2
                  echo "  You may need to fix this manually after installation." >&2
                fi
              fi
            fi
            
            # grub-mkconfig sometimes doesn't detect encrypted root in chroot
            # Manually add cryptdevice parameter if missing
            if ! grep -q "cryptdevice=" /boot/grub/grub.cfg 2>/dev/null; then
              echo "Warning: grub-mkconfig didn't add cryptdevice parameter. Attempting to add manually..." >&2
              
              # Use the LUKS UUID we already found (from installed disk)
              luks_uuid="$installed_luks_uuid"
              
              # Fallback: Try to find LUKS UUID if we didn't get it earlier
              if [[ -z "$luks_uuid" ]]; then
                # Method 1: Try common partition numbers (p2, p3, 2, 3)
                for part_suffix in "p2" "p3" "2" "3"; do
                  if [[ -b "${root_disk}${part_suffix}" ]]; then
                    part_type=$(blkid -s TYPE -o value "${root_disk}${part_suffix}" 2>/dev/null || echo "")
                    if [[ "$part_type" == "crypto_LUKS" ]]; then
                      luks_uuid=$(blkid -s UUID -o value "${root_disk}${part_suffix}" 2>/dev/null || echo "")
                      break
                    fi
                  fi
                done
              fi
              
              # Method 2: Scan all partitions on the disk for LUKS
              if [[ -z "$luks_uuid" ]]; then
                for part in $(lsblk -n -o NAME "$root_disk" 2>/dev/null | grep -E "^${root_disk##*/}p?[0-9]+$" || true); do
                  if [[ -b "/dev/$part" ]]; then
                    part_type=$(blkid -s TYPE -o value "/dev/$part" 2>/dev/null || echo "")
                    if [[ "$part_type" == "crypto_LUKS" ]]; then
                      luks_uuid=$(blkid -s UUID -o value "/dev/$part" 2>/dev/null || echo "")
                      if [[ -n "$luks_uuid" ]]; then
                        break
                      fi
                    fi
                  fi
                done
              fi
              
              # Method 3: Try to find from /etc/crypttab or mount info (with sudo if needed)
              if [[ -z "$luks_uuid" ]]; then
                if [[ -f /etc/crypttab ]] && [[ -r /etc/crypttab ]]; then
                  luks_line=$(grep -v "^#" /etc/crypttab | grep -v "^$" | head -1)
                  if [[ -n "$luks_line" ]]; then
                    luks_dev=$(echo "$luks_line" | awk '{print $2}')
                    if [[ -n "$luks_dev" ]] && [[ "$luks_dev" =~ ^UUID= ]]; then
                      luks_uuid=$(echo "$luks_dev" | sed 's/UUID=//')
                    fi
                  fi
                elif sudo test -f /etc/crypttab 2>/dev/null; then
                  luks_line=$(sudo grep -v "^#" /etc/crypttab 2>/dev/null | grep -v "^$" | head -1)
                  if [[ -n "$luks_line" ]]; then
                    luks_dev=$(echo "$luks_line" | awk '{print $2}')
                    if [[ -n "$luks_dev" ]] && [[ "$luks_dev" =~ ^UUID= ]]; then
                      luks_uuid=$(echo "$luks_dev" | sed 's/UUID=//')
                    fi
                  fi
                fi
              fi
              
              if [[ -n "$luks_uuid" ]]; then
                # Add cryptdevice to all linux lines that don't have it
                sudo sed -i "s|\(linux.*root=UUID=[^ ]*\) rw|\1 cryptdevice=UUID=${luks_uuid}:rootfs rw|g" /boot/grub/grub.cfg
                sudo sed -i "s|\(linux.*root=UUID=[^ ]*\) single|\1 cryptdevice=UUID=${luks_uuid}:rootfs single|g" /boot/grub/grub.cfg
                echo "Added cryptdevice=UUID=${luks_uuid}:rootfs to GRUB config" >&2
              else
                echo "Warning: Could not determine LUKS UUID. cryptdevice parameter not added." >&2
                echo "You may need to add it manually: cryptdevice=UUID=<LUKS_UUID>:rootfs" >&2
              fi
            fi
          fi
          
          # Create i386-coreboot directory for future modules
          sudo mkdir -p /boot/grub/i386-coreboot
          echo "Created /boot/grub/i386-coreboot/ directory for modules (to be built post-install)"
        else
          # No Libreboot GRUB payload - install Limine in BIOS/MBR mode
          if command -v limine-install &>/dev/null; then
            echo "Installing Limine bootloader to $root_disk in BIOS mode..."
            sudo limine-install "$root_disk" || {
              echo "Warning: limine-install failed. This may be normal if Limine was already installed." >&2
            }
          else
            echo "Warning: limine-install command not found. Limine may not be properly installed in BIOS mode." >&2
          fi
        fi
        
        # Create post-install instructions file (only for Libreboot)
        if [[ "$LIBREBOOT_GRUB" == "true" ]]; then
          sudo tee /root/LIBREBOOT_GRUB_MODULES_INSTRUCTIONS.txt >/dev/null <<'INSTRUCTIONS'
Libreboot GRUB Payload - Module Build Instructions
==================================================

Your system has been installed with Libreboot GRUB payload support, but
i386-coreboot modules need to be built for the system to boot.

The system will NOT boot until these modules are built and installed.

To build and install i386-coreboot modules:

1. Boot from a live ISO (CachyOS or Arch)
2. Mount your installed system
3. Follow the instructions in NEXT_STEPS.md or use Libreboot's build system (lbmk)

Quick reference:
  - Clone: git clone https://codeberg.org/libreboot/lbmk.git
  - Build: ./mk grub
  - Copy modules to: /boot/grub/i386-coreboot/

See the project documentation for detailed instructions.
INSTRUCTIONS
          echo "Created instructions file at /root/LIBREBOOT_GRUB_MODULES_INSTRUCTIONS.txt"
          
          # Log GRUB installation details
          if [[ -n "${OMARCHY_INSTALL_LOG_FILE:-}" ]]; then
            echo "[$(date +%Y-%m-%d\ %H:%M:%S)] GRUB installed for Libreboot (i386-pc target)" >> "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null || true
            echo "[$(date +%Y-%m-%d\ %H:%M:%S)] GRUB modules location: /boot/grub/i386-pc/" >> "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null || true
            echo "[$(date +%Y-%m-%d\ %H:%M:%S)] i386-coreboot directory created: /boot/grub/i386-coreboot/" >> "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null || true
            echo "[$(date +%Y-%m-%d\ %H:%M:%S)] Root disk: $root_disk" >> "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null || true
          fi
        fi
      fi
    fi
  fi

  # Remove the original config file if it's not /boot/limine.conf
  if [[ "$limine_config" != "/boot/limine.conf" ]] && [[ -f "$limine_config" ]]; then
    sudo rm "$limine_config"
  fi

  # We overwrite the whole thing knowing the limine-update will add the entries for us
  sudo cp $OMARCHY_PATH/default/limine/limine.conf /boot/limine.conf


  # Match Snapper configs if not installing from the ISO
  if [[ -z ${OMARCHY_CHROOT_INSTALL:-} ]]; then
    if ! sudo snapper list-configs 2>/dev/null | grep -q "root"; then
      sudo snapper -c root create-config /
    fi

    if ! sudo snapper list-configs 2>/dev/null | grep -q "home"; then
      sudo snapper -c home create-config /home
    fi
  fi

  # Enable quota to allow space-aware algorithms to work
  sudo btrfs quota enable /

  # Tweak default Snapper configs
  sudo sed -i 's/^TIMELINE_CREATE="yes"/TIMELINE_CREATE="no"/' /etc/snapper/configs/{root,home}
  sudo sed -i 's/^NUMBER_LIMIT="50"/NUMBER_LIMIT="5"/' /etc/snapper/configs/{root,home}
  sudo sed -i 's/^NUMBER_LIMIT_IMPORTANT="10"/NUMBER_LIMIT_IMPORTANT="5"/' /etc/snapper/configs/{root,home}
  sudo sed -i 's/^SPACE_LIMIT="0.5"/SPACE_LIMIT="0.3"/' /etc/snapper/configs/{root,home}
  sudo sed -i 's/^FREE_LIMIT="0.2"/FREE_LIMIT="0.3"/' /etc/snapper/configs/{root,home}

  chrootable_systemctl_enable limine-snapper-sync.service
fi

echo "Re-enabling mkinitcpio hooks..."

# Restore the specific mkinitcpio pacman hooks
if [ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled ]; then
  sudo mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled /usr/share/libalpm/hooks/90-mkinitcpio-install.hook
fi

if [ -f /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled ]; then
  sudo mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
fi

echo "mkinitcpio hooks re-enabled"

sudo limine-update

if [[ -n $EFI ]] && efibootmgr &>/dev/null; then
    # Remove the archinstall-created Limine entry
  while IFS= read -r bootnum; do
    sudo efibootmgr -b "$bootnum" -B >/dev/null 2>&1
  done < <(efibootmgr | grep -E "^Boot[0-9]{4}\*? Arch Linux Limine" | sed 's/^Boot\([0-9]\{4\}\).*/\1/')
fi

# Move this to a utility to allow manual activation
# if [[ -n $EFI ]] && efibootmgr &>/dev/null &&
#   ! cat /sys/class/dmi/id/bios_vendor 2>/dev/null | grep -qi "American Megatrends" &&
#   ! cat /sys/class/dmi/id/bios_vendor 2>/dev/null | grep -qi "Apple"; then
#
#   uki_file=$(find /boot/EFI/Linux/ -name "omarchy*.efi" -printf "%f\n" 2>/dev/null | head -1)
#
#   if [[ -n "$uki_file" ]]; then
#     sudo efibootmgr --create \
#       --disk "$(findmnt -n -o SOURCE /boot | sed 's/p\?[0-9]*$//')" \
#       --part "$(findmnt -n -o SOURCE /boot | grep -o 'p\?[0-9]*$' | sed 's/^p//')" \
#       --label "Omarchy" \
#       --loader "\\EFI\\Linux\\$uki_file"
#   fi
# fi
