# Set links for Nautilus action icons
mkdir -p /usr/share/icons/Yaru/scalable/actions
ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg \
          /usr/share/icons/Yaru/scalable/actions/go-previous-symbolic.svg
ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg \
          /usr/share/icons/Yaru/scalable/actions/go-next-symbolic.svg

# Chromium policy directory for theme
mkdir -p /etc/chromium/policies/managed
chmod a+rw /etc/chromium/policies/managed

# Default Chromium to follow system appearance ("device") instead of dark
mkdir -p /usr/lib/chromium
echo '{"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}' > \
  /usr/lib/chromium/initial_preferences
