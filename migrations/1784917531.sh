echo "Unpack the initramfs synchronously so Plymouth survives early boot"

# Kernel 7.1 unpacks the initramfs asynchronously, which races /init: the
# early /proc, /sys, /dev, and /run mounts fail while unpacking settles, so
# plymouthd exits when it can't read /proc/cmdline and encrypted boots fall
# back to an unthemed text LUKS prompt. Force synchronous unpacking until the
# race is fixed upstream. The packaged omarchy-defaults.conf now carries the
# same parameter for fresh installs.

if omarchy-cmd-present limine-mkinitcpio &&
  [[ -f /etc/limine-entry-tool.d/omarchy-defaults.conf ]] &&
  ! grep -rqs "initramfs_async" /etc/limine-entry-tool.d/ /etc/default/limine; then
  echo 'KERNEL_CMDLINE[default]+=" initramfs_async=0"' |
    sudo tee -a /etc/limine-entry-tool.d/omarchy-defaults.conf >/dev/null

  sudo limine-mkinitcpio
fi
