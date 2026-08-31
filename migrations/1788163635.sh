echo "Remove legacy temporary passwordless sudo grants"

# This removes current numeric grants, exact legacy username grants, corrupt or
# orphaned state, and their known timers. Administrator-authored sudoers files
# whose contents do not exactly match Omarchy's generated grammar are preserved.
sudo /usr/bin/omarchy-sudo-passwordless __cleanup-all
