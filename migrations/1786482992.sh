echo "Rebuild the boot image when it predates the Limine kernel command line"

# 1784917531 gated its rebuild on initramfs_async=0 being present in the Limine
# config, but omarchy-settings ships omarchy-defaults.conf with that parameter
# already in it. On a machine that installed the package and ran the migration
# in the same update, the guard matched the config the package had just
# written, skipped the rebuild, and left a boot image baked before the config
# landed. Such a machine boots without any of omarchy-defaults.conf's command
# line — including initramfs_async=0, so Plymouth still loses the LUKS prompt.

defaults_conf="${OMARCHY_LIMINE_DEFAULTS_CONF:-/etc/limine-entry-tool.d/omarchy-defaults.conf}"
running_cmdline="${OMARCHY_RUNNING_CMDLINE:-/proc/cmdline}"
rebuild_marker="${OMARCHY_LIMINE_REBUILD_MARKER:-/var/lib/omarchy/migrations/1786482992}"

omarchy-cmd-present limine-mkinitcpio || exit 0
[[ -f $defaults_conf && -r $running_cmdline ]] || exit 0

# The running kernel keeps its old command line until reboot, so a marker
# records the machine-wide rebuild instead: another user's migration must not
# repeat it before then, while a missing marker still retries an interrupted
# rebuild.
[[ ! -e $rebuild_marker ]] || exit 0

booted=$(<"$running_cmdline")
missing=()

for param in $(sed -n 's/^KERNEL_CMDLINE\[default\]+="\(.*\)"[[:space:]]*$/\1/p' "$defaults_conf"); do
  [[ " $booted " == *" $param "* ]] || missing+=("$param")
done

(( ${#missing[@]} )) || exit 0

echo "The booted kernel is missing ${missing[*]}; rebuilding the boot image"
sudo limine-mkinitcpio
sudo install -Dm644 /dev/null "$rebuild_marker"
