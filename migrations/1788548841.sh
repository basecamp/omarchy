echo "Refresh the duress boot files and convert leftover header tokens"

# The wrapper now treats a generic luks2 token as the duress mark so luksDump
# does not name the feature. Enrollment used to write type omarchy-duress;
# convert that leftover after the UKI is rebuilt with the new wrapper.

[[ -f /etc/mkinitcpio.conf.d/zz-omarchy-duress.conf ]] || exit 0

"$OMARCHY_PATH/bin/omarchy-setup-security-duress" --refresh-boot
