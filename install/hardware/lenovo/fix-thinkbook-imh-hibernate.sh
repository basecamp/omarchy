# Fix hibernate never powering off on Lenovo ThinkBook X IMH (21NW)
# After writing the hibernation image, the firmware's S4 entry never completes:
# the machine stays on with a frozen screen and only a forced power-off
# recovers it, while resume itself works fine. Kernel docs recommend shutdown
# mode for machines whose platform S4 handling is broken: the kernel powers
# the system off itself after writing the image, and resume still works from
# the swap signature on next boot.
# References:
# https://docs.kernel.org/power/basic-pm-debugging.html
# https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate

if omarchy-hw-match "ThinkBook X IMH"; then
  echo "Detected ThinkBook X IMH. Switching hibernation to shutdown mode..."

  sudo mkdir -p /etc/systemd/sleep.conf.d
  sudo tee /etc/systemd/sleep.conf.d/hibernatemode.conf >/dev/null <<'EOF'
[Sleep]
HibernateMode=shutdown
EOF
fi
