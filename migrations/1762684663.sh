echo "Ensure Linux is running fully preemptible to avoid video/audio issues"

if ! grep -q "preempt=full" /etc/default/limine; then
  sudo sed -i 's/^\(KERNEL_CMDLINE\[default\]+=\"[^"]*\)"/\1 preempt=full"/' /etc/default/limine
  sudo limine-update
  omarchy-state set reboot-required
fi
