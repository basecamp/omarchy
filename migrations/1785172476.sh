echo "Pre-build the theme, background, and unlock menu thumbnails"

# Unlock logos and previews are now generated from each theme's palette instead
# of being committed per theme. Build them, and the selector thumbnails, up
# front so no menu pays for it on its first open.
omarchy-cache-warm
