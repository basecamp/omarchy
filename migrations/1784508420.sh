echo "Enable WiFi 7 on Intel BE211 with Linux 7.1 or newer"

enable_be211_wifi7() {
  local wifi7_config="/etc/modprobe.d/iwlwifi-disable-eht.conf"
  local wifi7_backup="${wifi7_config}.omarchy-1784508420-backup"
  local kernel_modules_dir="/usr/lib/modules"
  local expected_config
  local actual_config
  local kernel_found=false
  local kernel_blocked=false
  local -a rebuild_command
  local comparison
  local extra
  local package_query
  local pkgbase_file
  local package
  local pci_devices
  local queried_package
  local version

  expected_config=$(printf '%s\n' \
    '# Temporary fix Dell XPS 14/16 on Panther lake' \
    '# Disable WiFi 7 (EHT) on Intel BE200/BE211 — broken RX rate adaptation' \
    '# Remove this file when fixes land in the iwlwifi EHT data path' \
    'options iwlwifi disable_11be=Y')

  if omarchy-cmd-present limine-mkinitcpio; then
    rebuild_command=(sudo limine-mkinitcpio)
  else
    rebuild_command=(sudo mkinitcpio -P)
  fi

  if [[ ! -f $wifi7_config && -f $wifi7_backup ]]; then
    actual_config=$(sudo cat "$wifi7_backup")
    if [[ $actual_config == "$expected_config" ]]; then
      if ! sudo mv "$wifi7_backup" "$wifi7_config"; then
        echo "ERROR: Failed to restore $wifi7_config from interrupted migration"
        return 1
      fi
      if ! "${rebuild_command[@]}"; then
        echo "ERROR: Failed to rebuild boot images after interrupted migration"
        return 1
      fi
      omarchy-state set reboot-required ||
        echo "WARNING: Failed to mark reboot-required after restoring $wifi7_config"
    else
      echo "Unable to restore unexpected backup $wifi7_backup"
      return 1
    fi
  fi

  if ! pci_devices=$(lspci -nn); then
    echo "Skipped $wifi7_config because PCI devices could not be inspected"
    return 0
  fi

  [[ $pci_devices == *"[8086:e440]"* ]] || return 0

  if [[ $pci_devices == *"[8086:272b]"* ]]; then
    echo "Skipped $wifi7_config because Intel BE200 is also present"
    return 0
  fi

  for pkgbase_file in "$kernel_modules_dir"/*/pkgbase; do
    [[ -f $pkgbase_file ]] || continue

    package=$(<"$pkgbase_file")
    if ! package_query=$(pacman -Q "$package" 2>/dev/null); then
      kernel_blocked=true
      break
    fi

    read -r queried_package version extra <<<"$package_query"
    if [[ $package_query == *$'\n'* || $queried_package != "$package" || -z $version || -n $extra ]]; then
      kernel_blocked=true
      break
    fi

    if ! comparison=$(vercmp "$version" 7.1 2>/dev/null) || [[ ! $comparison =~ ^-?[0-9]+$ ]]; then
      kernel_blocked=true
      break
    fi

    kernel_found=true
    if (( comparison < 0 )); then
      kernel_blocked=true
      break
    fi
  done

  if ! $kernel_found || $kernel_blocked; then
    echo "Skipped $wifi7_config because not all installed kernels are Linux 7.1 or newer"
    return 0
  fi

  [[ -f $wifi7_config ]] || return 0

  actual_config=$(sudo cat "$wifi7_config")
  if [[ $actual_config != "$expected_config" ]]; then
    echo "Skipped $wifi7_config because it is not the Omarchy-managed workaround"
    return 0
  fi

  if [[ -e $wifi7_backup ]]; then
    echo "Unable to migrate while backup already exists at $wifi7_backup"
    return 1
  fi

  sudo mv "$wifi7_config" "$wifi7_backup" || return 1

  if ! "${rebuild_command[@]}"; then
    if ! sudo mv "$wifi7_backup" "$wifi7_config"; then
      echo "ERROR: Failed to restore $wifi7_config after migration failure"
      return 1
    fi

    if ! "${rebuild_command[@]}"; then
      echo "ERROR: Failed to rebuild boot images with the restored WiFi workaround"
    fi
    return 1
  fi

  sudo rm -f "$wifi7_backup" ||
    echo "WARNING: Failed to remove $wifi7_backup; delete it manually"

  omarchy-state set reboot-required ||
    echo "WARNING: Failed to mark reboot-required; reboot to apply the WiFi 7 change"

  return 0
}

enable_be211_wifi7
