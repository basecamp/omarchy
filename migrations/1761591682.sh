#!/usr/bin/env bash
echo "Create NetworkManager configuration file"

conf_dir="/etc/NetworkManager/conf.d"
sudo cp -f ~/.local/share/omarchy/default/networkmanager/omarchy_networkmanager.conf "$conf_dir/omarchy_networkmanager.conf"

# Check for other .conf files in conf.d/ (ignore backups)
other_files=$(find "$conf_dir" -maxdepth 1 -type f -name "*.conf" \
    ! -name "omarchy_networkmanager.conf" \
    ! -name "*.bak.*")

if [ -n "$other_files" ]; then
    echo "WARNING: There are other configuration files in $conf_dir that might override Omarchy configuration:"
    echo "$other_files"
fi

