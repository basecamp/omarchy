#!/bin/bash
#
# Install omarchy-arm's libinput quirks file system-wide.
#
# The source file (default/libinput/local-overrides.quirks) is tracked
# in the repo and gets updated via omarchy-update. This script copies
# it to /etc/libinput/local-overrides.quirks at install time.
#
# The shipped quirk only matches the keyd virtual keyboard by name, so
# on systems without keyd it's inert — safe to install unconditionally.

echo "Installing libinput quirks for omarchy-arm..."

SRC="$OMARCHY_PATH/default/libinput/local-overrides.quirks"
DEST=/etc/libinput/local-overrides.quirks

if [ ! -f "$SRC" ]; then
  echo "Source quirks file missing: $SRC"
  echo "Skipping libinput quirks install."
  return 0 2>/dev/null || exit 0
fi

sudo install -D -m 644 "$SRC" "$DEST"

echo "libinput quirks installed to $DEST"
