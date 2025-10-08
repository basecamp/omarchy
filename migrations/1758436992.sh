#!/bin/bash
# Migration: Clean Chromium GPU and shader caches to fix color issues after upgrade

set -e

browser=$(xdg-settings get default-web-browser)

case $browser in
google-chrome* | brave-browser* | microsoft-edge* | opera* | vivaldi* | helium-browser*) ;;
*) browser="chromium.desktop" ;;
esac

BROWSER=${browser%.desktop}

# Directories to remove
CACHE_DIRS=(
    "$HOME/.config/$BROWSER/GrShaderCache"
    "$HOME/.config/$BROWSER/ShaderCache"
    "$HOME/.config/$BROWSER/Default/GPUCache"
)

for dir in "${CACHE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "Removing $dir..."
        rm -rf "$dir"
    fi

done

echo "Chromium GPU and shader caches cleaned."
