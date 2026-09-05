# Set default XCompose that is triggered with CapsLock.
#
# The emoji table ships under $OMARCHY_PATH, but sandboxed apps (Steam's
# pressure-vessel, Flatpaks) bind-mount $HOME and not the host /usr. An
# absolute include into /usr/share/omarchy fails to open there, and xkbcommon
# aborts the whole compose file — every sequence dies, not only the Omarchy
# ones. Keep a home-local copy and include it with %H so containers that see
# $HOME still parse the table.
packaged_xcompose="${OMARCHY_PATH}/default/xcompose"
home_xcompose="$HOME/.XCompose.omarchy"

if [[ -f $packaged_xcompose ]]; then
  cp "$packaged_xcompose" "$home_xcompose"
  chmod 644 "$home_xcompose"
fi

tee ~/.XCompose >/dev/null <<EOF
# Run omarchy-restart-xcompose to apply changes

# Include fast emoji access
include "%H/.XCompose.omarchy"

# Identification
<Multi_key> <space> <n> : "$OMARCHY_USER_NAME"
<Multi_key> <space> <e> : "$OMARCHY_USER_EMAIL"
EOF
