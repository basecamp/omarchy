# Add custom keybindings to the Omarchy keybindings menu (Super + K).
# See $OMARCHY_PATH/bin/omarchy-menu-keybindings for the expected output format.
#
# $OMARCHY_PATH/bin/omarchy-menu-keybindings will invoke a user_bindings()
# function in this file if present.
#
# Each line output by user_bindings() must be comma-separated:
#   MODIFIERS,KEY,Description
#
# Example:
# user_bindings() {
#   echo ",prefix h,Tmux: split pane vertically"
#   echo ",prefix v,Tmux: split pane horizontally"
#   echo "ALT,1,Tmux: window 1"
#   echo "CTRL ALT,Left,Tmux: navigate pane left"
#   echo "ALT,1,Tmux: window 1"
