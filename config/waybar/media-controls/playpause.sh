#!/bin/bash

players=$(playerctl -l 2>/dev/null)
player=""

# Prefer Playing, then Paused
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

if [[ -z "$player" ]]; then
    echo '{"text": " ", "tooltip": "", "class": ""}'
    exit 0
fi

status=$(playerctl --player="$player" status 2>/dev/null)

case "$status" in
Playing)
    icon="" # pause icon
    tooltip="Pause"
    ;;
Paused)
    icon="" # play icon
    tooltip="Play"
    ;;
*)
    echo '{"text": " ", "tooltip": "", "class": ""}'
    exit 0
    ;;
esac

echo "{\"text\": \"$icon\", \"tooltip\": \"$tooltip\"}"
