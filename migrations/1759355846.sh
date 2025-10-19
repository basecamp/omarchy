echo "Symlink systemd-resolved to /etc/resolv.conf"

# Backup if /etc/resolv.conf was modified after system birth
system_birth=$(stat -c %W /)
resolvconf_modified=$(stat -c %Y /etc/resolv.conf)

# Run a backup if resolv.conf isn't a symlink and was modified after install
if [[ -s /etc/resolv.conf ]] && [[ ! -L /etc/resolv.conf ]] && [[ $resolvconf_modified > $system_birth ]]; then
  # Backup the destination file (with timestamp) to avoid clobbering (Ex: resolv.conf.bak.1753817951)
  backup_file="/etc/resolv.conf.bak.$(date +%s)"

  # Create backup
  sudo cp -f /etc/resolv.conf "$backup_file" 2>/dev/null

  # Inform users
  echo -e "\e[31mReplaced /etc/resolv.conf with symlink to systemd-resolved. \nSaved backup as ${backup_file}.\e[0m"
  echo -e "\e[31mSee https://wiki.archlinux.org/title/Systemd-resolved.\e[0m"
fi

# Write the symlink
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
