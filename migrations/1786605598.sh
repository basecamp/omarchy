echo "Rebuild the initramfs so NVIDIA-only systems shed nouveau's unused GSP firmware"

# omarchy_hooks.conf now filters the kms hook out of HOOKS when the proprietary
# NVIDIA driver handles early KMS and NVIDIA owns every display controller
# (#6790). The settings package deploys that conditional, but nothing rebuilds
# the initramfs for a mkinitcpio drop-in change, so affected machines would
# carry ~100 MB of dead nouveau firmware until their next kernel update.
# Rebuild once, and only where the conditional actually changes the outcome:
# evaluate the installed drop-ins the way mkinitcpio does and check that kms
# dropped out. A user-edited omarchy_hooks.conf (pacman leaves the packaged
# update as a .pacnew) keeps kms and correctly skips the rebuild.

hooks_conf="${OMARCHY_MKINITCPIO_HOOKS_CONF:-/etc/mkinitcpio.conf.d/omarchy_hooks.conf}"
nvidia_conf="${OMARCHY_MKINITCPIO_NVIDIA_CONF:-/etc/mkinitcpio.conf.d/nvidia.conf}"
rebuild_marker="${OMARCHY_KMS_REBUILD_MARKER:-/var/lib/omarchy/migrations/1786605598}"

omarchy-cmd-present limine-mkinitcpio || exit 0
[[ -f $hooks_conf && -f $nvidia_conf ]] || exit 0

# The rebuild is machine-wide, but migrations run once per user: a marker
# records completion so another user's run does not repeat it, while a missing
# marker still retries an interrupted rebuild.
[[ ! -e $rebuild_marker ]] || exit 0

# Source the drop-ins in mkinitcpio's order (nvidia.conf sorts first) and read
# the HOOKS they produce. Skip conservatively if evaluation fails.
hooks=$(bash -c 'source "$1" && source "$2" && echo " ${HOOKS[*]} "' -- "$nvidia_conf" "$hooks_conf") || exit 0

[[ $hooks != *" kms "* ]] || exit 0

echo "This machine no longer uses the kms hook; rebuilding the initramfs without nouveau"
sudo limine-mkinitcpio
sudo install -Dm644 /dev/null "$rebuild_marker"
