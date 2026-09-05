echo "Install Grok chat and Grok Build launchers"

# The grok.com chat webapp used to exist only as Super+Shift+Alt+A. Copying
# the shipped desktop files puts it in Apps as Grok, and the coding agent as
# Grok Build, so the two stop sharing a name. Refresh overwrites matching
# local copies so existing installs pick up the rename.
mkdir -p "$HOME/.local/share/applications"
cp "$OMARCHY_PATH/applications/Grok.desktop" "$HOME/.local/share/applications/Grok.desktop"
cp "$OMARCHY_PATH/applications/Grok Build.desktop" "$HOME/.local/share/applications/Grok Build.desktop"
