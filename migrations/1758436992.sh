#!/bin/bash
# Migration: Clean Chromium GPU and shader caches to fix color issues after upgrade

set -e

# Directories to remove
CACHE_DIRS=(
    "$HOME/.config/google-chrome/GrShaderCache"
    "$HOME/.config/google-chrome/ShaderCache"
    "$HOME/.config/google-chrome/Default/GPUCache"
)

for dir in "${CACHE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "Removing $dir..."
        rm -rf "$dir"
    fi

done

echo "Chromium GPU and shader caches cleaned."
