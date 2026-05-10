#!/bin/bash

# Smart config merge for overlay/dualboot modes

merge_config() {
    local config_type="$1"
    local default_config="$OMARCHY_PATH/default/$config_type"
    local user_config="$HOME/.config/$config_type"
    local mode="${OMARCHY_INSTALL_MODE:-fresh}"

    # Fresh mode: simple overwrite
    if [[ "$mode" == "fresh" ]]; then
        if [[ -d "$default_config" ]]; then
            mkdir -p "$(dirname "$user_config")"
            cp -rf "$default_config" "$user_config"
            echo "Copied default $config_type config"
        fi
        return 0
    fi

    # Overlay/Dualboot: smart merge
    if [[ ! -d "$default_config" ]]; then
        echo "No default config for $config_type, skipping"
        return 0
    fi

    if [[ -f "$user_config" ]] || [[ -d "$user_config" ]]; then
        # Backup existing config
        local backup="$user_config.backup.$(date +%Y%m%d-%H%M%S)"
        cp -r "$user_config" "$backup"
        echo "Backed up existing $config_type config to $(basename "$backup")"

        # Merge: copy new files, don't overwrite existing
        cp -rn "$default_config"/* "$user_config"/
        echo "Merged $config_type config (user config preserved)"
    else
        # No existing config - use default
        mkdir -p "$(dirname "$user_config")"
        cp -r "$default_config" "$user_config"
        echo "Created new $config_type config from defaults"
    fi
}

merge_all_configs() {
    local configs=("hypr" "waybar" "swayosd" "dunst" "foot" "kitty")

    for config in "${configs[@]}"; do
        if [[ -d "$OMARCHY_PATH/default/$config" ]]; then
            merge_config "$config"
        fi
    done
}

# Export functions for use in other scripts
export -f merge_config
export -f merge_all_configs