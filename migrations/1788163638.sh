echo "Repair the permissions and inode of the Omarchy installer log"

helper=/usr/share/omarchy/install/helpers/logging.sh
current=$helper

[[ -e /var/log/omarchy-install.log || -L /var/log/omarchy-install.log ]] || exit 0

# This migration deliberately invokes only the package-owned helper at its
# fixed installed path. Never source OMARCHY_PATH (which belongs to the caller)
# in a privileged shell.
while :; do
  [[ -e $current && ! -L $current ]] || {
    echo "Cannot trust the installed Omarchy logging helper path: $current" >&2
    exit 1
  }
  owner=$(/usr/bin/stat -c '%u' -- "$current") || exit 1
  mode=$(/usr/bin/stat -c '%a' -- "$current") || exit 1
  [[ $owner == 0 && $mode =~ ^[0-7]+$ ]] && ! ((8#$mode & 0022)) || {
    echo "The installed Omarchy logging helper path is writable by an untrusted account: $current" >&2
    exit 1
  }
  [[ $current == / ]] && break
  current=$(/usr/bin/dirname -- "$current") || exit 1
done

[[ $(/usr/bin/realpath -e -- "$helper") == "$helper" && -f $helper ]] || {
  echo "The installed Omarchy logging helper is not a regular canonical file." >&2
  exit 1
}

# prepare_install_log_file is idempotent but intentionally publishes a new
# inode on every run. That detaches file descriptors opened while old Omarchy
# releases left this exact log mode 0666. Unsafe symlinks, special files, and
# foreign-owned anomalies are preserved and make the migration retry.
/usr/bin/sudo -N -- /usr/bin/env -i PATH=/usr/bin:/bin \
  OMARCHY_INSTALL_LOG_FILE=/var/log/omarchy-install.log \
  /usr/bin/bash -euo pipefail -c '
    source /usr/share/omarchy/install/helpers/logging.sh
    prepare_install_log_file
  '
