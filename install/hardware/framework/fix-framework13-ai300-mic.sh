OMARCHY_FRAMEWORK13_AI300_MIC_REBUILT=0

if omarchy-hw-framework13-ai300; then
  mic_conf="${OMARCHY_FRAMEWORK13_AI300_MIC_CONF:-/etc/modprobe.d/omarchy-framework13-ai300-mic.conf}"
  rebuild_marker="${OMARCHY_FRAMEWORK13_AI300_MIC_REBUILD_MARKER:-/var/lib/omarchy/hardware/framework13-ai300-mic-fix}"
  desired_config='# Framework Laptop 13 AMD Ryzen AI 300 microphone workaround.
# Disable the unusable ACP capture path so the Realtek ALC285 HDA microphone remains selectable.
blacklist snd_acp70
blacklist snd_acp_pci'

  if ! cmp -s <(printf '%s\n' "$desired_config") "$mic_conf"; then
    sudo rm -f "$rebuild_marker"
    printf '%s\n' "$desired_config" |
      sudo install -Dm644 /dev/stdin "$mic_conf"
  fi

  if [[ ! -e $rebuild_marker ]]; then
    sudo limine-mkinitcpio
    sudo install -Dm644 /dev/null "$rebuild_marker"
    OMARCHY_FRAMEWORK13_AI300_MIC_REBUILT=1
  fi
fi
