# Set default XCompose that is triggered with CapsLock
tee ~/.XCompose >/dev/null <<EOF
# Run omarchy-restart-xcompose to apply changes

# Include fast emoji access
include "/usr/share/omarchy/default/xcompose"

# Identification
<Multi_key> <space> <n> : "$OMARCHY_USER_NAME"
<Multi_key> <space> <e> : "$OMARCHY_USER_EMAIL"
EOF

# US International puts ç behind ' + c, but the compose table an English locale
# loads reads dead_acute + c as ć, the Slavic letter. pt_BR.UTF-8's table
# overrides exactly this pair for the same reason; do it here so the layout the
# installer offers behaves like the one it is named after. Keyed off the variant
# the keyboard step already persisted, so no other layout is touched.
vconsole_config="${OMARCHY_VCONSOLE_CONFIG:-/etc/vconsole.conf}"

if [[ -f $vconsole_config ]] &&
  [[ $(unset XKBVARIANT; . "$vconsole_config"; echo "${XKBVARIANT:-}") == "intl" ]]; then
  tee -a ~/.XCompose >/dev/null <<'CEDILLA'

# Cedilla, not C with acute, on the US International layout
<dead_acute> <c> : "ç" ccedilla
<dead_acute> <C> : "Ç" Ccedilla
CEDILLA
fi
