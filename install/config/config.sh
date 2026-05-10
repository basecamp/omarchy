# Copy over Omarchy configs
mkdir -p ~/.config

# Source config merge helper
source "$OMARCHY_INSTALL/helpers/config-merge.sh" 2>/dev/null || true

# For overlay/dualboot, merge configs instead of overwrite
if [[ "$OMARCHY_INSTALL_MODE" != "fresh" ]]; then
    echo "Merging configs (overlay/dualboot mode)..."
    merge_all_configs
fi

cp -R ~/.local/share/omarchy/config/* ~/.config/

# Use default bashrc from Omarchy
cp ~/.local/share/omarchy/default/bashrc ~/.bashrc
