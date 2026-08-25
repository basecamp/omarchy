# Set links for Nautilus action icons
mkdir -p /usr/share/icons/Yaru/scalable/actions
ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg \
          /usr/share/icons/Yaru/scalable/actions/go-previous-symbolic.svg
ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg \
          /usr/share/icons/Yaru/scalable/actions/go-next-symbolic.svg
gtk-update-icon-cache /usr/share/icons/Yaru &>/dev/null || true

# Chromium policy directory for theme. This is an enterprise policy trust root:
# Chromium reads every JSON file here as administrator-managed policy, so it
# stays root-owned and not writable by ordinary users.
# omarchy-theme-set-browser-policy takes root of its own to write color.json.
install -d -m 0755 -o root -g root /etc/chromium/policies/managed

# Default Chromium to follow system appearance ("device") instead of dark
mkdir -p /usr/lib/chromium
echo '{"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}' > \
  /usr/lib/chromium/initial_preferences
