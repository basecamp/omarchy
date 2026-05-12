# Extend or override the Quickshell Omarchy menu.
#
# This file is sourced by $OMARCHY_PATH/bin/omarchy-menu after the default menu
# is built. Add options with the small DSL below, or replace an existing action by
# assigning MENU_ACTIONS[existing.id].
#
#   menu_group  <parent-id> <id> <icon> <label> [keywords] [description]
#   menu_link   <parent-id> <id> <icon> <label> <target-menu-id> [keywords] [description]
#   menu_action <parent-id> <id> <icon> <label> <command> [keywords] [description]
#
# Example: add a personal submenu to the main screen.
#
# menu_group "root" "personal" "" "Personal" "notes projects"
# menu_action "personal" "personal.notes" "󰎞" "Notes" "omarchy-launch-editor ~/notes" "notes"
# menu_action "personal" "personal.files" "" "Files" "uwsm-app -- nautilus ~/Documents" "files documents"
#
# Example: replace the default About action.
#
# MENU_ACTIONS[root.about]="omarchy-launch-or-focus-tui \"zsh -c 'fastfetch; read -k 1'\""
#
# Example: actions may call helper functions defined in this file.
#
# open_notes() {
#   omarchy-launch-editor ~/notes
# }
#
# menu_action "personal" "personal.notes" "󰎞" "Notes" "open_notes" "notes"
