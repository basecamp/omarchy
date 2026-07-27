# Defer plocate indexing out of the ISO install critical path. A synchronous
# updatedb here can cost several seconds on a fresh tree — enough to miss a
# sub-minute install — and locate is not needed before the first reboot.
#
# Enable an idle first-boot oneshot (via a short OnBootSec timer) instead so
# the desktop is not blocked; daily plocate-updatedb.timer keeps the index
# fresh afterwards.
systemctl enable omarchy-updatedb-first-boot.timer
