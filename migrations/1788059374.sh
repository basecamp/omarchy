echo "Retire static system files left outside package ownership"

path_is_unowned() {
  local path=$1
  local report status

  if report=$(LC_ALL=C pacman -Qo "$path" 2>&1); then
    return 1
  else
    status=$?
  fi

  if (( status == 1 )) && [[ $report == "error: No package owns $path" ]]; then
    return 0
  fi

  echo "Unable to verify package ownership for $path: $report" >&2
  return 2
}

regular_file_without_following() {
  local path=$1
  local parent=${path%/*}
  local kind status

  if [[ -L $path ]]; then
    return 1
  elif [[ -f $path ]]; then
    return 0
  elif [[ -x $parent ]]; then
    return 1
  fi

  # Root-only directories such as /etc/sudoers.d require a privileged stat.
  if kind=$(sudo /usr/bin/env LC_ALL=C /usr/bin/stat --format=%F -- "$path" 2>&1); then
    [[ $kind == "regular file" ]]
    return
  else
    status=$?
  fi

  if (( status == 1 )) && [[ $kind == *"No such file or directory" ]]; then
    return 1
  fi

  echo "Unable to inspect legacy path $path: $kind" >&2
  return 2
}

remove_known_unowned_file() {
  local path=$1
  local current_sha256 known_sha256 ownership_status type_status
  shift

  # Do not follow a symlink or read from a device/FIFO at a legacy path.
  if regular_file_without_following "$path"; then
    :
  else
    type_status=$?
    if (( type_status == 1 )); then
      return
    else
      return "$type_status"
    fi
  fi

  if path_is_unowned "$path"; then
    :
  else
    ownership_status=$?
    if (( ownership_status == 1 )); then
      return
    else
      return "$ownership_status"
    fi
  fi

  if ! current_sha256=$(sudo sha256sum -- "$path" | awk '{ print $1 }'); then
    echo "Unable to hash legacy path $path" >&2
    return 2
  fi
  for known_sha256; do
    if [[ $current_sha256 == "$known_sha256" ]]; then
      sudo rm -f -- "$path"
      return
    fi
  done
}

# Early Quattro upgrades wrote SDDM's own defaults back as an unowned drop-in.
remove_known_unowned_file \
  /etc/sddm.conf.d/99-omarchy-login.conf \
  f19d407fd64f5bd73d72949fe1269fb57ce3575eba52ae836c2ad667ad9741a5 \
  9490578ced7bc5b656d871e4a439b13386cbd2ae2ef6f80e655b65b915c05fd3

# Omarchy 3 configured SDDM with a Hyprland text config. Quattro packages the
# replacement Lua config, so retire only the exact obsolete source.
remove_known_unowned_file \
  /usr/share/sddm/hyprland.conf \
  73bdfb956a679d2b26cc3773ed7865a7202e90694a5a2b6e1ca0ca7d4731097a

# These paths were renamed when their replacements moved into
# omarchy-settings. Preserve local edits; remove only the values Omarchy 3
# wrote verbatim.
remove_known_unowned_file \
  /etc/modprobe.d/disable-usb-autosuspend.conf \
  52c54cf62584130627ae3a3c3d83b6153a2f832dd2e03aa11db516ee2c7574c1
remove_known_unowned_file \
  /etc/sudoers.d/passwd-tries \
  fb2225f7f666aa730957c7dedc6cabb3532be5913c1a58b684d5b928bce2ccdb
remove_known_unowned_file \
  /etc/systemd/system/user@.service.d/faster-shutdown.conf \
  1dd0343bcd5a30b8309f5eb07527da1d64f6c9a8e93d909a6ac050d926d65796
remove_known_unowned_file \
  /etc/systemd/system.conf.d/99-omarchy-nofile.conf \
  18b7162f6ceeed5bcf305dcd512426add3fee2abd774de032c2ce5a6e9629853 \
  8818b84990ce08b9409ef4db4ea971c9c82fad4562e61bb2f52d838127654ee3
remove_known_unowned_file \
  /etc/systemd/user.conf.d/99-omarchy-nofile.conf \
  18b7162f6ceeed5bcf305dcd512426add3fee2abd774de032c2ce5a6e9629853 \
  8818b84990ce08b9409ef4db4ea971c9c82fad4562e61bb2f52d838127654ee3

legacy_asdcontrol=/etc/sudoers.d/asdcontrol
migration_user=$(id -un)
asdcontrol_usr_sha256=$(printf '%s\n' "$migration_user ALL=(ALL) NOPASSWD: /usr/bin/asdcontrol" | sha256sum | awk '{ print $1 }')
asdcontrol_local_sha256=$(printf '%s\n' "$migration_user ALL=(ALL) NOPASSWD: /usr/local/bin/asdcontrol" | sha256sum | awk '{ print $1 }')
remove_known_unowned_file "$legacy_asdcontrol" "$asdcontrol_usr_sha256" "$asdcontrol_local_sha256"

# Omarchy 3 appended this line to a conventionally local sysctl file. The same
# setting is now package-owned under 99-omarchy-sysctl.conf, so remove only the
# exact old line and retain everything else.
legacy_sysctl=/etc/sysctl.d/99-sysctl.conf
if [[ -f $legacy_sysctl && ! -L $legacy_sysctl ]]; then
  if path_is_unowned "$legacy_sysctl"; then
    if grep_report=$(sudo grep -q '^net\.ipv4\.tcp_mtu_probing=1$' "$legacy_sysctl" 2>&1); then
      sudo sed -i '/^net\.ipv4\.tcp_mtu_probing=1$/d' "$legacy_sysctl"
    else
      grep_status=$?
      if (( grep_status != 1 )) || [[ -n $grep_report ]]; then
        echo "Unable to inspect legacy path $legacy_sysctl: $grep_report" >&2
        exit 2
      fi
    fi
  else
    ownership_status=$?
    if (( ownership_status != 1 )); then
      exit "$ownership_status"
    fi
  fi
fi
