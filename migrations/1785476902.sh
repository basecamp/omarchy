echo "Install wl-clip-persist so the clipboard survives closing the app it was copied from"

# On Wayland the copying app owns the clipboard, so closing it (browser,
# password manager popup, etc.) silently empties the clipboard even though
# the entry still shows in the clipboard history. wl-clip-persist takes
# ownership of every selection so pasting keeps working.
omarchy-pkg-add wl-clip-persist

# Start it in the running session too; autostart.lua covers future logins.
if ! pgrep -x wl-clip-persist >/dev/null; then
  uwsm-app -- wl-clip-persist --clipboard regular --all-mime-type-regex '^(?!x-kde-passwordManagerHint).+' &>/dev/null &
fi
