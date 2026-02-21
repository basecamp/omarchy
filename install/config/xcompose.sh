# Set default XCompose that is triggered with CapsLock
tee ~/.XCompose >/dev/null <<EOF
# Run omarchy-restart-xcompose to apply changes

# Include fast emoji access
include "%H/.local/share/omarchy/default/xcompose"

# Identification
<Multi_key> <space> <n> : "$OMARCHY_USER_NAME"
<Multi_key> <space> <e> : "$OMARCHY_USER_EMAIL"
EOF
