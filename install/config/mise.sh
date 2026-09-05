MISE_CONFIG_PATH="${OMARCHY_MISE_CONFIG_PATH:-/etc/mise/config.toml}"

install -Dm644 "$OMARCHY_PATH/default/mise/config.toml" "$MISE_CONFIG_PATH"
