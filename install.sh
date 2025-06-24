# Install everything
for f in ~/.local/share/omarchy/install/*.sh; do source "$f"; done

# Ensure locate is up to date now that everything has been installed
sudo updatedb

gum confirm "Reboot to apply all settings?" && reboot
