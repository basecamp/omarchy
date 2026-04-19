# Install Intel Low Power Mode Daemon for supported hybrid Intel CPUs (Alder Lake and newer)
# Supported models: Alder Lake (151/154), Raptor Lake (183/186/191),
# Meteor Lake (170/172), Lunar Lake (189), Panther Lake (204)

lpmd_config_path() {
  local cpu_family cpu_model candidate config_path

  cpu_family=$(grep -m1 "^cpu family" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | tr -d ' ')
  cpu_model=$(grep -m1 "^model\s*:" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | tr -d ' ')

  for candidate in /etc/intel_lpmd/intel_lpmd_config_F${cpu_family}_M${cpu_model}_T*.xml; do
    [[ -f $candidate ]] || continue
    config_path=$candidate
    break
  done

  if [[ -z $config_path ]]; then
    candidate="/etc/intel_lpmd/intel_lpmd_config_F${cpu_family}_M${cpu_model}.xml"
    [[ -f $candidate ]] && config_path=$candidate
  fi

  if [[ -z $config_path ]]; then
    candidate="/etc/intel_lpmd/intel_lpmd_config.xml"
    [[ -f $candidate ]] && config_path=$candidate
  fi

  printf '%s\n' "$config_path"
}

configure_lpmd_defaults() {
  local config_path

  config_path=$(lpmd_config_path)
  [[ -n $config_path ]] || return 0

  # Let intel-lpmd follow power-profiles-daemon directly.
  sudo xmlstarlet ed -L \
    -u "/Configuration/PerformanceDef" -v "-1" \
    -u "/Configuration/BalancedDef" -v "0" \
    -u "/Configuration/PowersaverDef" -v "1" \
    "$config_path"
}

if omarchy-hw-intel && omarchy-battery-present; then
  cpu_model=$(grep -m1 "^model\s*:" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | tr -d ' ')
  if [[ $cpu_model =~ ^(151|154|170|172|183|186|189|191|204)$ ]]; then
    omarchy-pkg-add intel-lpmd
    configure_lpmd_defaults
    sudo systemctl enable intel_lpmd.service
    sudo rm -f /etc/sudoers.d/omarchy-intel-lpmd
  fi
fi
