#!/bin/bash

# Set up yay wrapper to use local PKGBUILDs if available
echo "Setting up AUR package management..."

if [[ -n "$OMARCHY_PKGBUILD_CACHE" ]] && [[ -d "$OMARCHY_PKGBUILD_CACHE" ]]; then
    echo "✓ Using local PKGBUILD cache: $OMARCHY_PKGBUILD_CACHE"
    
    # Set up yay wrapper only if yay exists
    if command -v yay &>/dev/null && [[ ! -f /tmp/yay-wrapped ]]; then
        # Backup original yay
        sudo cp /usr/bin/yay /usr/bin/yay.original 2>/dev/null || true
        
        # Install our wrapper - find it relative to the omarchy root
        OMARCHY_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
        if [[ -f "$OMARCHY_ROOT/bin/omarchy-yay-wrapper" ]]; then
            sudo cp "$OMARCHY_ROOT/bin/omarchy-yay-wrapper" /usr/bin/yay
        else
            echo "Warning: omarchy-yay-wrapper not found, skipping wrapper setup"
        fi
        
        # Mark that we've wrapped it
        touch /tmp/yay-wrapped
        
        echo "✓ yay wrapper installed"
    fi
else
    echo "⚠ No PKGBUILD cache configured, using standard AUR"
fi