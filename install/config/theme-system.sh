# Set links for Nautilus action icons
mkdir -p /usr/share/icons/Yaru/scalable/actions
ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg \
          /usr/share/icons/Yaru/scalable/actions/go-previous-symbolic.svg
ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg \
          /usr/share/icons/Yaru/scalable/actions/go-next-symbolic.svg
gtk-update-icon-cache /usr/share/icons/Yaru &>/dev/null || true

# Chromium policy directory for theme. omarchy-theme-set-browser writes the theme
# colour file (color.json) here as the user, so give the directory to that user at
# 0755 rather than making it world-writable: a world-writable managed-policy
# directory lets any local user or process force a mandatory browser policy -- an
# extension forcelist, a proxy, disabled Safe Browsing.
mkdir -p /etc/chromium/policies/managed
if [[ -n ${OMARCHY_INSTALL_USER:-} ]]; then
  chown "$OMARCHY_INSTALL_USER:$(id -gn "$OMARCHY_INSTALL_USER")" /etc/chromium/policies/managed
fi
chmod 755 /etc/chromium/policies/managed

# Default Chromium to follow system appearance ("device") instead of dark
mkdir -p /usr/lib/chromium
echo '{"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}' > \
  /usr/lib/chromium/initial_preferences
