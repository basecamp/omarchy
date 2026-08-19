# Set default XCompose that is triggered with CapsLock
if [[ ! -f $HOME/.XCompose ]]; then
  cat >"$HOME/.XCompose" <<EOF
# Run omarchy-restart-xcompose to apply changes

# Include fast emoji access
include "/usr/share/omarchy/default/xcompose"

# Identification
<Multi_key> <space> <n> : "$OMARCHY_USER_NAME"
<Multi_key> <space> <e> : "$OMARCHY_USER_EMAIL"
EOF
fi
