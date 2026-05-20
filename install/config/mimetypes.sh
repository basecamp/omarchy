# MIME default mappings now ship as config/mimeapps.list (via /etc/skel for
# new users; existing users keep their own). This script only handles the
# runtime side: refresh applications and set Chromium as the system default
# web browser. (omarchy-install-browser overrides this if the user picks
# something else later.)
omarchy-refresh-applications
xdg-settings set default-web-browser chromium.desktop
