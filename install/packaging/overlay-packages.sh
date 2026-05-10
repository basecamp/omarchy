#!/bin/bash

# Overlay mode: install only Omarchy-specific packages

install_omarchy_overlay_packages() {
    local mode="${OMARCHY_INSTALL_MODE:-fresh}"
    
    if [[ "$mode" != "overlay" ]]; then
        return 0
    fi
    
    echo "Installing Omarchy packages only (overlay mode)..."
    
    local omarchy_packages=(
        "waybar"
        "hyprland"
        "swayosd"
        "omarchy-keyring"
        "plymouth"
        "limine-snapper-sync"
        "foot"
        "dunst"
        "mako"
        "wofi"
    )
    
    for pkg in "${omarchy_packages[@]}"; do
        if omarchy-pkg-present "$pkg" 2>/dev/null; then
            echo "$pkg already installed"
        else
            echo "Installing $pkg..."
            omarchy-pkg-add "$pkg" || warn "Failed to install $pkg"
        fi
    done
    
    echo "Omarchy overlay packages installed"
}

export -f install_omarchy_overlay_packages