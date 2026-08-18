echo "Point T2 overlay Limine at /boot/efi and write a linux-t2 entry"

# Overlay installs from t2archinstall keep the ESP at /boot/efi and leave /boot
# as a directory on btrfs. Omarchy Limine still has ESP_PATH=/boot, so
# limine-update writes the branding-only template where Apple firmware never
# looks and toasts "Target OS name 'Omarchy' not found" (#7347 sections 1–2).
# Official installs already use /boot as the ESP and are left alone.

if ! lspci -nn | grep "106b:180[12]" >/dev/null; then
  exit 0
fi

boot_mount="${OMARCHY_T2_BOOT:-/boot}"
esp_mount="${OMARCHY_T2_ESP:-/boot/efi}"
limine_default="${OMARCHY_T2_LIMINE_DEFAULT:-/etc/default/limine}"
reset_enroll="${OMARCHY_T2_RESET_ENROLL:-/etc/boot/hooks/pre.d/10-limine-reset-enroll}"
cmdline_file="${OMARCHY_T2_RUNNING_CMDLINE:-/proc/cmdline}"

if [[ ${OMARCHY_T2_BOOT_FSTYPE+set} == set ]]; then
  boot_fstype=$OMARCHY_T2_BOOT_FSTYPE
else
  boot_fstype=$(findmnt -no FSTYPE "$boot_mount" 2>/dev/null || true)
fi

if [[ ${OMARCHY_T2_ESP_FSTYPE+set} == set ]]; then
  esp_fstype=$OMARCHY_T2_ESP_FSTYPE
else
  esp_fstype=$(findmnt -no FSTYPE "$esp_mount" 2>/dev/null || true)
fi

if [[ $boot_fstype == "vfat" ]]; then
  exit 0
fi

if [[ $esp_fstype != "vfat" ]]; then
  exit 0
fi

if [[ ! -f $limine_default ]] || ! grep -Eq '^ESP_PATH=["'\'']?/boot/efi["'\'']?$' "$limine_default"; then
  if [[ -f $limine_default ]] && grep -q '^ESP_PATH=' "$limine_default"; then
    sudo sed -i 's|^ESP_PATH=.*|ESP_PATH="/boot/efi"|' "$limine_default"
  else
    printf 'ESP_PATH="/boot/efi"\n' | sudo tee -a "$limine_default" >/dev/null
  fi
fi

copy_kernel_to_esp() {
  local src=$1
  local dest=$2

  if [[ ! -f $src ]]; then
    return 0
  fi

  if [[ -f $dest ]] && cmp -s "$src" "$dest"; then
    return 0
  fi

  sudo install -Dm644 "$src" "$dest"
}

copy_kernel_to_esp "$boot_mount/vmlinuz-linux-t2" "$esp_mount/vmlinuz-linux-t2"
copy_kernel_to_esp "$boot_mount/initramfs-linux-t2.img" "$esp_mount/initramfs-linux-t2.img"

cmdline=""
if [[ -r $cmdline_file ]]; then
  cmdline=$(<"$cmdline_file")
  cmdline=${cmdline%%$'\n'}
fi

has_linux_t2_entry() {
  local conf=$1

  [[ -f $conf ]] || return 1

  awk '
    $0 == "/Omarchy" { expect_kernel = 1; next }
    expect_kernel {
      expect_kernel = 0
      if ($0 == "//linux-t2") {
        in_kernel = 1
        next
      }
    }
    in_kernel && /^[[:space:]]*protocol:[[:space:]]*linux[[:space:]]*$/ {
      found = 1
      exit
    }
    in_kernel && /^\// { in_kernel = 0 }
    END { exit !found }
  ' "$conf"
}

write_linux_t2_entry() {
  local conf=$1

  if has_linux_t2_entry "$conf"; then
    return 0
  fi

  if [[ ! -f $conf ]]; then
    local template="${OMARCHY_PATH:-/usr/share/omarchy}/default/limine/limine.conf"
    if [[ -f $template ]]; then
      sudo install -Dm644 "$template" "$conf"
    else
      sudo install -Dm644 /dev/null "$conf"
    fi
  fi

  sudo tee -a "$conf" >/dev/null <<EOF

/Omarchy
//linux-t2
    protocol: linux
    path: boot():/vmlinuz-linux-t2
    cmdline: $cmdline
    module_path: boot():/initramfs-linux-t2.img
EOF
}

if [[ -f $esp_mount/vmlinuz-linux-t2 ]]; then
  write_linux_t2_entry "$esp_mount/limine.conf"

  if [[ -d $esp_mount/EFI/BOOT ]]; then
    write_linux_t2_entry "$esp_mount/EFI/BOOT/limine.conf"
  fi

  if [[ -d $esp_mount/EFI/limine ]]; then
    write_linux_t2_entry "$esp_mount/EFI/limine/limine.conf"
  fi
fi

# The reset hook rewrites the enrolled Limine config and can put branding-only
# back on this ESP. Disable it the way limine-entry-tool documents.
if [[ -e $reset_enroll ]]; then
  sudo mv "$reset_enroll" "${reset_enroll}.disabled"
fi
