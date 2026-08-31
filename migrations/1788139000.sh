echo "Hide kernel pointers from unprivileged /proc readers"

# Package updates deliver etc/sysctl.d/99-omarchy-sysctl.conf with
# kernel.kptr_restrict=1, but existing boots keep the prior runtime value until
# the next reboot unless we load the file now. Apply only our drop-in so an
# unrelated invalid key elsewhere cannot fail the migration.
if [[ -r /etc/sysctl.d/99-omarchy-sysctl.conf ]]; then
  sudo sysctl -p /etc/sysctl.d/99-omarchy-sysctl.conf >/dev/null 2>&1 || true
fi
