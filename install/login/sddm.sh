# Install omarchy SDDM theme
rm -rf /usr/share/sddm/themes/omarchy
mkdir -p /usr/share/sddm/themes
cp -r "$OMARCHY_PATH/default/sddm/omarchy" /usr/share/sddm/themes/omarchy

# Setup SDDM login service
mkdir -p /usr/local/share/wayland-sessions
cp -f "$OMARCHY_PATH/default/wayland-sessions/omarchy.desktop" /usr/local/share/wayland-sessions/omarchy.desktop
cp -f "$OMARCHY_PATH/default/sddm/hyprland.lua" /usr/share/sddm/hyprland.lua
rm -rf /usr/share/sddm/hyprland.conf

mkdir -p /etc/sddm.conf.d
autologin_conf=/etc/sddm.conf.d/autologin.conf
if [[ ! -f $autologin_conf ]]; then
  cat > "$autologin_conf" <<EOF
[Autologin]
User=${OMARCHY_INSTALL_USER:-${USER:-}}
Session=omarchy
EOF
else
  sed -i 's/^Session=hyprland-uwsm$/Session=omarchy/' "$autologin_conf"
  sed -i '/^\[Theme\]$/,/^$/d' "$autologin_conf"
fi

# Prevent password-based SDDM logins from creating an encrypted login keyring
# (which conflicts with the passwordless Default_keyring used for auto-unlock)
if [[ -f /etc/pam.d/sddm ]]; then
  sed -i '/-auth.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
  sed -i '/-password.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
fi
