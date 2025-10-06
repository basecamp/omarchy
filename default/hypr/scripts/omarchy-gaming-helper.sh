#!/bin/bash

# Gaming Helper for Hyprland
# Runs as a service in the background to perform tasks that can't be accomplished with only 
# hyprland rules
# Usage: omarchy-gaming-helper.sh [--debug]

DEBUG_MODE=0
[[ "$1" == "--debug" ]] && DEBUG_MODE=1

# Track if we have active games
GAMES_ACTIVE=0

log_debug() {
    [[ $DEBUG_MODE -eq 1 ]] && gum log --level debug "$@"
}

log_info() {
    gum log --level info "$@"
}

# Monitor Management
apply_gaming_scale() {
    log_info "Applying integer scaling for gaming"

    # Get all monitors and apply integer scaling
    hyprctl monitors -j | jq -r '.[] | "\(.name) \(.width) \(.height) \(.refreshRate) \(.x) \(.y) \(.scale)"' | \
    while read -r name width height refresh x y scale; do
        # Round scale to nearest integer
        integer_scale=$(awk "BEGIN {printf \"%.0f\", $scale}")

        log_info "Setting $name from scale $scale to $integer_scale"
        hyprctl keyword monitor "$name,${width}x${height}@${refresh},${x}x${y},$integer_scale"
    done
}

restore_monitor_settings() {
    log_info "Restoring monitor settings"
    hyprctl reload
}

# Game Detection
is_steam_game() {
    local class="$1"
    [[ "$class" == steam_app_* ]]
}

count_active_games() {
    hyprctl clients -j | jq -r '[.[] | select(.class | startswith("steam_app_"))] | length'
}

# Event Handlers
handle_window_open() {
    local event="$1"

    # Parse: openwindow>>address,workspace,class,title
    IFS=',' read -r address workspace class title <<< "${event#openwindow>>}"

    if is_steam_game "$class"; then
        log_info "Steam game opened: $title ($class)"

        # Apply scaling on first game
        if [[ $GAMES_ACTIVE -eq 0 ]]; then
            apply_gaming_scale
        fi
        GAMES_ACTIVE=$((GAMES_ACTIVE + 1))

        # Apply fullscreen
        hyprctl dispatch fullscreenstate 2 2 "address:$address"
    fi
}

handle_title_change() {
    local event="$1"

    # Parse: windowtitlev2>>address,title
    IFS=',' read -r address title <<< "${event#windowtitlev2>>}"
    address="${address#0x}"

    # Get window class and tags
    local window_info=$(hyprctl clients -j | jq -r --arg addr "0x$address" \
        '.[] | select(.address == $addr) | "\(.class) \(.tags)"')

    if [[ -z "$window_info" ]]; then
        return
    fi

    read -r class tags <<< "$window_info"

    # Handle gamescope windows (Battle.net, etc)
    if [[ "$class" == "gamescope" ]]; then
        if [[ "$tags" == *"game"* ]] && [[ "$tags" != *"game-launcher"* ]]; then
            log_info "Gamescope game detected: $title"
            hyprctl dispatch fullscreenstate 2 2 "address:0x$address"
        elif [[ "$tags" == *"game-launcher"* ]]; then
            log_info "Gamescope launcher detected: $title"
            hyprctl dispatch fullscreenstate 0 0 "address:0x$address"
        fi
    fi
}

handle_window_close() {
    local event="$1"
    local address="${event#closewindow>>}"

    # Count remaining games
    local remaining_games=$(count_active_games)
    log_debug "Window closed, remaining games: $remaining_games"

    # Restore settings when last game closes
    if [[ "$remaining_games" -eq 0 ]] && [[ $GAMES_ACTIVE -gt 0 ]]; then
        log_info "No games remain, restoring settings"
        restore_monitor_settings
        GAMES_ACTIVE=0
    else
        GAMES_ACTIVE="$remaining_games"
    fi
}

# Main Event Loop
main() {
    log_info "Gaming helper started (debug=$DEBUG_MODE)"

    socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | \
    while read -r event; do
        log_debug "Event: ${event:0:80}..."

        case "$event" in
            openwindow*)
                handle_window_open "$event"
                ;;
            windowtitlev2*)
                handle_title_change "$event"
                ;;
            closewindow*)
                handle_window_close "$event"
                ;;
        esac
    done
}

# Start
main
