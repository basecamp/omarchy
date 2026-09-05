# Apple dual-GPU Macs expose the panel backlight as gmux_backlight on the PNP
# bus. systemd's path_id builtin fails for that device, so 99-systemd.rules
# never sets SYSTEMD_WANTS and systemd-backlight never starts. After a reboot
# the firmware default comes back (about 18% on these panels) instead of the
# brightness the user last set.
#
# This rule starts systemd-backlight without needing ID_PATH. The service still
# saves under /var/lib/systemd/backlight/backlight:gmux_backlight when path_id
# cannot supply a name.
udev_rules_dir="${OMARCHY_UDEV_RULES_DIR:-/etc/udev/rules.d}"
backlight_path="${OMARCHY_BACKLIGHT_PATH:-/sys/class/backlight}"
dmi_vendor="${OMARCHY_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}"
rule_src="$OMARCHY_PATH/default/udev/gmux-backlight.rules"
rule_dest="$udev_rules_dir/99-omarchy-gmux-backlight.rules"

sys_vendor="$(cat "$dmi_vendor" 2>/dev/null || true)"

if [[ -e $backlight_path/gmux_backlight || $sys_vendor == Apple* ]]; then
  echo "Detected Apple GMUX backlight; enabling systemd-backlight save/restore"

  sudo mkdir -p "$udev_rules_dir"
  if [[ ! -f $rule_dest ]]; then
    sudo cp -f "$rule_src" "$rule_dest"
  fi

  # Best-effort on a live session so this shutdown already saves. The ISO chroot
  # has no running udev/systemd for the target, and a missing binary must not
  # abort hardware setup.
  sudo udevadm control --reload-rules 2>/dev/null || true
  sudo udevadm trigger --action=add --subsystem-match=backlight --sysname-match=gmux_backlight 2>/dev/null || true
  sudo systemctl start systemd-backlight@backlight:gmux_backlight.service 2>/dev/null || true
fi
