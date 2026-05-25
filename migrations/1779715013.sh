echo "Install mise package wrappers"

rm -f "$HOME/.local/bin/playwright-cli"
omarchy-pkg-drop claude-code github-cli

source "$OMARCHY_PATH/install/packaging/mise.sh"
