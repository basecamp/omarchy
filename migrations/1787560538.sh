echo "Switch ThinkBook X IMH hibernation to shutdown mode"

# After writing the hibernation image, this model's firmware never completes
# the S4 entry: the machine stays on with a frozen screen until a forced
# power-off, while resume works fine. HibernateMode=shutdown lets the kernel
# power the system off itself after writing the image. Same rationale as
# install/hardware/lenovo/fix-thinkbook-imh-hibernate.sh.
if ! omarchy-hw-match "ThinkBook X IMH"; then
  exit 0
fi

hibernate_mode_conf="${OMARCHY_HIBERNATE_MODE_CONF:-/etc/systemd/sleep.conf.d/hibernatemode.conf}"

if [[ -f $hibernate_mode_conf ]] && grep -q '^HibernateMode=shutdown$' "$hibernate_mode_conf"; then
  exit 0
fi

sudo mkdir -p /etc/systemd/sleep.conf.d
sudo tee "$hibernate_mode_conf" >/dev/null <<'EOF'
[Sleep]
HibernateMode=shutdown
EOF
