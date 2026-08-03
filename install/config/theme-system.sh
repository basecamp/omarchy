# Set links for Nautilus action icons
mkdir -p /usr/share/icons/Yaru/scalable/actions
ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg \
          /usr/share/icons/Yaru/scalable/actions/go-previous-symbolic.svg
ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg \
          /usr/share/icons/Yaru/scalable/actions/go-next-symbolic.svg
gtk-update-icon-cache /usr/share/icons/Yaru &>/dev/null || true

# Chromium policy directory for theme
mkdir -p /etc/chromium/policies/managed
# Pre-create a user-owned color.json so omarchy-theme-set-browser can update
# the theme color without write access to the root-owned policy directory.
printf '%s\n' '{"BrowserThemeColor": "#1c2027", "BrowserColorScheme": "device"}' > \
  /etc/chromium/policies/managed/color.json
chown "$OMARCHY_INSTALL_USER:" /etc/chromium/policies/managed/color.json

# Default Chromium to follow system appearance ("device") instead of dark
mkdir -p /usr/lib/chromium
echo '{"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}' > \
  /usr/lib/chromium/initial_preferences
