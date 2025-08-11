#!/bin/bash
trap '' SIGPIPE

# Find active player: prefer Playing, then Paused
players=$(playerctl -l 2>/dev/null)
player=""

for p in $players; do
    status=$(playerctl --player="$p" status 2>/dev/null)
    if [[ "$status" == "Playing" ]]; then
        player=$p
        break
    fi
done

if [[ -z "$player" ]]; then
    for p in $players; do
        status=$(playerctl --player="$p" status 2>/dev/null)
        if [[ "$status" == "Paused" ]]; then
            player=$p
            break
        fi
    done
fi

# No active player, output empty JSON
if [[ -z "$player" ]]; then
    echo '{"text": " ", "tooltip": "", "class": ""}'
    exit 0
fi

status=$(playerctl --player="$player" status 2>/dev/null)
artist=$(playerctl --player="$player" metadata xesam:artist 2>/dev/null | head -n 1)
title=$(playerctl --player="$player" metadata xesam:title 2>/dev/null)

if [[ -z "$status" || -z "$title" ]]; then
    echo '{"text": " ", "tooltip": "", "class": ""}'
    exit 0
fi

declare -A player_icons=(
    ["chromium"]=""
    ["firefox"]=""
    ["kdeconnect"]=""
    ["mopidy"]=""
    ["mpv"]="󰐹"
    ["spotify"]=""
    ["vlc"]="󰕼"
    ["strawberry"]=""
    ["default"]=""
)

icon="${player_icons[$player]:-${player_icons["default"]}}"

tooltip="$artist - $title"
# Escape ampersands and quotes to avoid markup errors
escaped_tooltip=$(printf '%s' "$tooltip" | sed 's/&/\&amp;/g; s/"/\\"/g')

echo "{\"text\": \"$icon $artist - $title\", \"tooltip\": \"$escaped_tooltip\", \"class\": \"custom-media\"}"
