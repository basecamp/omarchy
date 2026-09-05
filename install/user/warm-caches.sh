# Pre-build the theme, background, and unlock selector thumbnails so the first
# open of each menu is instant. Runs in the ISO chroot as the target user, so a
# freshly installed machine already has them and never pays for it at login.
omarchy-cache-warm
