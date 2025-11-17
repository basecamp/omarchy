#!/bin/bash
#
# Omarchy Final Configurations Installer
#
# This script runs from archinstall's custom_commands after base packages
# and user creation. It switches to the created user and runs install.sh
# to complete package installation and system configuration.
#
# archinstall runs custom_commands as root via:
#   arch-chroot -S /mnt bash /var/tmp/user-command.0.sh
#

set -eEo pipefail

# Setup comprehensive logging for chroot execution
# This ensures all output is captured even though we're running inside chroot
CHROOT_LOG_FILE="/var/log/omarchy-install-chroot.log"
mkdir -p "$(dirname "$CHROOT_LOG_FILE")"
touch "$CHROOT_LOG_FILE"

# Redirect all output to both the log file and stdout
# This way:
# 1. Output is saved to /var/log/omarchy-install-chroot.log (inside chroot = /mnt/var/log on ISO)
# 2. Output still goes to stdout so arch-chroot can potentially capture it
# 3. We use exec to redirect the entire script's output from this point forward
exec > >(tee -a "$CHROOT_LOG_FILE") 2>&1

# Log script start with timestamp
echo "========================================"
echo "Omarchy Chroot Install Starting"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Log file: $CHROOT_LOG_FILE"
echo "========================================"
echo

# Find the first non-root user (UID >= 1000, < 60000)
OMARCHY_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}')

if [[ -z "$OMARCHY_USER" ]]; then
    echo "ERROR: No non-root user found!"
    echo "Users created:"
    getent passwd | awk -F: '$3 >= 1000 {print $1, $3}'
    exit 1
fi

echo "Setting up Omarchy for user: $OMARCHY_USER"

# Setup passwordless sudo (will be removed by post-install)
echo "Setting up passwordless sudo..."
mkdir -p /etc/sudoers.d
cat >/etc/sudoers.d/99-omarchy-installer <<EOF
root ALL=(ALL:ALL) NOPASSWD: ALL
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
$OMARCHY_USER ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 440 /etc/sudoers.d/99-omarchy-installer

# Get user info from /tmp (written by configurator)
if [[ -f /tmp/omarchy-user-name.txt ]]; then
  OMARCHY_USER_NAME=$(cat /tmp/omarchy-user-name.txt)
else
  OMARCHY_USER_NAME=""
fi

if [[ -f /tmp/omarchy-user-email.txt ]]; then
  OMARCHY_USER_EMAIL=$(cat /tmp/omarchy-user-email.txt)
else
  OMARCHY_USER_EMAIL=""
fi

# Run install.sh as the user
echo "========================================"
echo "Running Omarchy installation as user: $OMARCHY_USER"
echo "========================================"
echo

# Use runuser instead of su for better output handling
# runuser doesn't go through PAM and preserves stdout/stderr better
runuser -u "$OMARCHY_USER" -- bash -c "
    set -eEo pipefail
    export PYTHONUNBUFFERED=1
    export OMARCHY_CHROOT_INSTALL=1
    export OMARCHY_ARCHINSTALL_WRAPPER=1
    export OMARCHY_USER='$OMARCHY_USER'
    export OMARCHY_USER_NAME='$OMARCHY_USER_NAME'
    export OMARCHY_USER_EMAIL='$OMARCHY_USER_EMAIL'
    cd ~
    source /usr/share/omarchy/install.sh
"

exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    echo
    echo "========================================"
    echo "Omarchy install.sh completed successfully!"
    echo "========================================"
    echo
    echo "========================================"
    echo "Omarchy Chroot Install Completed"
    echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Log file: $CHROOT_LOG_FILE"
    echo "========================================"
else
    echo
    echo "========================================"
    echo "ERROR: Omarchy install.sh exited with code $exit_code"
    echo "========================================"
    exit $exit_code
fi
