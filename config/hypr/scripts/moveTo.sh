#!/usr/bin/env bash
#                         __
#   __ _  ___ _  _____   / /____
#  /  ' \/ _ \ |/ / -_) / __/ _ \
# /_/_/_/\___/___/\__/  \__/\___/
#

# Function to log messages (useful for debugging)
log_message() {
    # echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> ~/moveto_log.txt
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Get the target workspace from the argument
target_workspace=$1

# Check if a target workspace was provided
if [ -z "$target_workspace" ]; then
    log_message "Error: No target workspace provided"
    exit 1
fi

# Get the current active workspace
current_workspace=$(hyprctl activewindow -j | jq '.workspace.id')

if [ -z "$current_workspace" ]; then
    log_message "Error: Couldn't determine current workspace"
    exit 1
fi

log_message "Moving from workspace $current_workspace to $target_workspace"

# Get all window addresses in the current workspace
window_addresses=$(hyprctl clients -j | jq -r ".[] | select(.workspace.id == $current_workspace) | .address")

# Move each window to the target workspace
for address in $window_addresses; do
    log_message "Moving window $address to workspace $target_workspace"
    hyprctl dispatch movetoworkspacesilent "$target_workspace,address:$address"
done

log_message "Finished moving windows"

# Switch to the target workspace
hyprctl dispatch workspace "$target_workspace"

log_message "Switched to workspace $target_workspace"
