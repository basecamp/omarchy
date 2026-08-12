echo "Unpack the initramfs synchronously so Plymouth survives early boot"

# Kernel 7.1 unpacks the initramfs asynchronously, which races /init: the
# early /proc, /sys, /dev, and /run mounts fail while unpacking settles, so
# plymouthd exits when it can't read /proc/cmdline and encrypted boots fall
# back to an unthemed text LUKS prompt. Force synchronous unpacking until the
# race is fixed upstream. default/limine/default.conf now carries the same
# parameter for fresh installs.

async_conf="${OMARCHY_LIMINE_ASYNC_CONF:-/etc/limine-entry-tool.d/omarchy-initramfs-async.conf}"
default_conf="${OMARCHY_LIMINE_DEFAULT_CONF:-/etc/default/limine}"
running_cmdline="${OMARCHY_RUNNING_CMDLINE:-/proc/cmdline}"
rebuild_marker="${OMARCHY_LIMINE_REBUILD_MARKER:-/var/lib/omarchy/migrations/1786479765}"

omarchy-cmd-present limine-mkinitcpio || exit 0

# Hardware fix scripts drop their own configs beside this one, and a fresh
# install already carries the parameter in the central config.
if ! grep -rqs "initramfs_async" "$(dirname "$async_conf")" "$default_conf"; then
  sudo mkdir -p "$(dirname "$async_conf")"
  sudo tee "$async_conf" >/dev/null <<'EOF'
# Kernel 7.1 unpacks the initramfs asynchronously, which races /init and drops
# Plymouth from the LUKS prompt. Unpack synchronously until the race is fixed
# upstream.
KERNEL_CMDLINE[default]+=" initramfs_async=0"
EOF
fi

# The running kernel keeps its old command line until reboot, so a marker
# records the machine-wide rebuild instead: another user's migration must not
# repeat it before then, while a missing marker still retries an interrupted
# rebuild.
[[ ! -e $rebuild_marker ]] || exit 0
[[ -r $running_cmdline ]] || exit 0

booted=$(<"$running_cmdline")
[[ " $booted " != *" initramfs_async=0 "* ]] || exit 0

sudo limine-mkinitcpio
sudo install -Dm644 /dev/null "$rebuild_marker"
