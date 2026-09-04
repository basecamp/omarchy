echo "Refresh the duress initramfs wrapper if a duress password is enrolled"

# Enrollment copies hook files into /usr/lib/initcpio. Package updates do not.
# Without this, a wrapper bugfix stays on disk in $OMARCHY_PATH and never
# reaches the UKI until the user re-runs setup.

[[ -f /etc/mkinitcpio.conf.d/zz-omarchy-duress.conf ]] || exit 0

"$OMARCHY_PATH/bin/omarchy-setup-security-duress" --refresh-boot
