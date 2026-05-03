echo "Drop /home snapshots, btrfs quotas, and timeline snapshots (keep 5 root snapshots, never more)"

if ! omarchy-cmd-present snapper btrfs; then
  exit 0
fi

# Disable btrfs quotas first — every subvolume delete below would otherwise update
# all qgroups, which is exactly the performance drag we're removing.
sudo btrfs quota disable / 2>/dev/null || true

# Remove the home config, all its snapshots, and the .snapshots subvolume.
# If the snapshots look like someone's been using them manually (pre/post pairs,
# userdata tags, freeform descriptions), ask before destroying.
if sudo snapper list-configs 2>/dev/null | grep -q "home"; then
  drop_home="yes"

  if sudo snapper -c home --csvout list 2>/dev/null | \
     awk -F, 'NR>1 && ($6=="pre" || $6=="post" || $13!="" || ($12!="current" && $12!="timeline" && $12 !~ /^[0-9]+\.[0-9]+\.[0-9]+/))' | \
     grep -q .; then
    gum confirm "Drop unused /home snapshots for better performance?" || drop_home="no"
  fi

  if [[ $drop_home == "yes" ]]; then
    sudo snapper -c home list --columns number 2>/dev/null | awk 'NR>2 && $1 != "0" {print $1}' | \
      xargs -r sudo snapper -c home delete 2>/dev/null
    sudo snapper -c home delete-config 2>/dev/null

    if [[ -d /home/.snapshots ]]; then
      for snap in /home/.snapshots/*/snapshot; do
        [[ -d $snap ]] && sudo btrfs subvolume delete "$snap" 2>/dev/null
      done
      sudo rm -rf /home/.snapshots/* 2>/dev/null
      sudo btrfs subvolume delete /home/.snapshots 2>/dev/null
    fi
  fi
fi

# Ensure root config exists and matches our shipped defaults
if ! sudo snapper list-configs 2>/dev/null | grep -q "root"; then
  sudo snapper -c root create-config /
fi
sudo cp $OMARCHY_PATH/default/snapper/root /etc/snapper/configs/root

# Delete all timeline snapshots — we only want pre-update (cleanup=number) snapshots
sudo snapper -c root list --columns number,cleanup 2>/dev/null | \
  awk '$3 == "timeline" {print $1}' | \
  xargs -r sudo snapper -c root delete 2>/dev/null

# Enforce NUMBER_LIMIT=5 on any existing number snapshots beyond the new cap
sudo snapper -c root cleanup number 2>/dev/null
