# Shared 15" Radeon MacBook helpers. Sourced; no shebang, no work on source.
# S3/s2idle do not resume. Lid locks. Polaris stays bound and POWER_SAVING.
# BCM43602 stays PCI-awake so a closed lid cannot D3 the radio.

mbp15_logind_dest() {
  printf '%s\n' "${OMARCHY_MBP15_LOGIND:-/etc/systemd/logind.conf.d/10-omarchy-apple-mbp15.conf}"
}

mbp15_sleep_dest() {
  printf '%s\n' "${OMARCHY_MBP15_SLEEP:-/etc/systemd/sleep.conf.d/10-omarchy-apple-mbp15.conf}"
}

mbp15_udev_src() {
  printf '%s\n' "${OMARCHY_MBP15_UDEV_SRC:-$OMARCHY_PATH/default/udev/apple-mbp15-amdgpu-idle.rules}"
}

mbp15_udev_dest() {
  printf '%s\n' "${OMARCHY_MBP15_UDEV_DEST:-/etc/udev/rules.d/90-omarchy-apple-mbp15-amdgpu-idle.rules}"
}

mbp15_wifi_udev_src() {
  printf '%s\n' "${OMARCHY_MBP15_WIFI_UDEV_SRC:-$OMARCHY_PATH/default/udev/apple-mbp15-wifi-pm.rules}"
}

mbp15_wifi_udev_dest() {
  printf '%s\n' "${OMARCHY_MBP15_WIFI_UDEV_DEST:-/etc/udev/rules.d/90-omarchy-apple-mbp15-wifi-pm.rules}"
}

mbp15_write_sleep_policy() {
  local dest
  dest=$(mbp15_logind_dest)
  mkdir -p "$(dirname "$dest")"
  cat >"$dest" <<'EOF'
# 15" 2016–2017 MacBook Pro (Radeon): S3 and s2idle never resume.
[Login]
HandleLidSwitch=lock
HandleLidSwitchExternalPower=lock
HandleLidSwitchDocked=ignore
EOF

  dest=$(mbp15_sleep_dest)
  mkdir -p "$(dirname "$dest")"
  cat >"$dest" <<'EOF'
# 15" 2016–2017 MacBook Pro (Radeon): do not offer S3/S4.
[Sleep]
AllowSuspend=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no
AllowHibernation=no
EOF
}

mbp15_write_amdgpu_idle() {
  local dest
  dest=$(mbp15_udev_dest)
  mkdir -p "$(dirname "$dest")"
  cp -f "$(mbp15_udev_src)" "$dest"
}

mbp15_write_wifi_pm() {
  local dest
  dest=$(mbp15_wifi_udev_dest)
  mkdir -p "$(dirname "$dest")"
  cp -f "$(mbp15_wifi_udev_src)" "$dest"
}

mbp15_apply() {
  mbp15_write_sleep_policy
  mbp15_write_amdgpu_idle
  mbp15_write_wifi_pm

  if [[ ${OMARCHY_MBP15_SKIP_SYSTEMCTL:-} == 1 ]]; then
    return 0
  fi

  systemctl reload systemd-logind.service || true
  command -v udevadm >/dev/null && udevadm control --reload || true
  command -v udevadm >/dev/null &&
    udevadm trigger --subsystem-match=pci --attr-match=vendor=0x14e4 --attr-match=device=0x43ba || true
  command -v omarchy-hw-apple-mbp15-amdgpu-idle >/dev/null &&
    omarchy-hw-apple-mbp15-amdgpu-idle || true
  command -v omarchy-hw-apple-mbp15-wifi-pm >/dev/null &&
    omarchy-hw-apple-mbp15-wifi-pm || true
}
