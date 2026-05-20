echo "Clean up the old per-script /etc files now owned by omarchy-settings package"

# ssh-flakiness.sh used to append `net.ipv4.tcp_mtu_probing=1` to the
# conventionally-user-owned /etc/sysctl.d/99-sysctl.conf. The setting now ships
# at /etc/sysctl.d/99-omarchy-sysctl.conf via the package. Strip the line from
# the old path if it's there (leave the rest of 99-sysctl.conf alone).
if [[ -f /etc/sysctl.d/99-sysctl.conf ]] && grep -q '^net\.ipv4\.tcp_mtu_probing=1' /etc/sysctl.d/99-sysctl.conf; then
  sudo sed -i '/^net\.ipv4\.tcp_mtu_probing=1$/d' /etc/sysctl.d/99-sysctl.conf
fi

# usb-autosuspend.sh used /etc/modprobe.d/disable-usb-autosuspend.conf; package
# now owns /etc/modprobe.d/omarchy-usb-autosuspend.conf. Remove the old file.
sudo rm -f /etc/modprobe.d/disable-usb-autosuspend.conf

# Sudoers renames: passwd-tries -> omarchy-passwd-tries; asdcontrol -> omarchy-asdcontrol.
sudo rm -f /etc/sudoers.d/passwd-tries
sudo rm -f /etc/sudoers.d/asdcontrol

# fast-shutdown.sh used to ship user@.service.d/faster-shutdown.conf; the
# package owns user@.service.d/10-faster-shutdown.conf. Both would apply
# simultaneously, so remove the old.
sudo rm -f /etc/systemd/system/user@.service.d/faster-shutdown.conf

# ignore-power-button.sh used to `sed` HandlePowerKey=ignore directly into
# /etc/systemd/logind.conf. The package now ships a drop-in at
# /etc/systemd/logind.conf.d/10-ignore-power-button.conf, which wins regardless,
# but reset the main file's line back to its commented default so future
# changes to the drop-in aren't shadowed.
if [[ -f /etc/systemd/logind.conf ]] && grep -q '^HandlePowerKey=ignore' /etc/systemd/logind.conf; then
  sudo sed -i 's/^HandlePowerKey=ignore$/#HandlePowerKey=poweroff/' /etc/systemd/logind.conf
fi

# Reload anything that watches these files so the changes take effect now.
sudo systemctl daemon-reload || true
sudo sysctl --system >/dev/null 2>&1 || true
