echo "Drop the retired notification image cache"

# Notification history used to be a pair of long-lived lists in
# notifications.json, and thumbnails for it were copied out of /tmp into this
# cache so they would outlive the screenshot they came from. History is now the
# last ten notification files under ~/.local/state/omarchy/notifications/history,
# which reference their image where it already lives, so nothing writes or reads
# this directory anymore.

rm -rf "$HOME/.cache/omarchy/notification-images"
