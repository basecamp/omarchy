echo "Symlink files needed for Nautilus navigation icons"

sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-previous-symbolic.svg
sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-next-symbolic.svg

# rebuild cache
sudo gtk-update-icon-cache /usr/share/icons/Yaru

echo "Close Files if running"
sudo -u ${SUDO_USER:-$USER} pkill nautilus