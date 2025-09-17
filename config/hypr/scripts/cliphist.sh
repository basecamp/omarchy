#!/usr/bin/env bash
#   ____ _ _       _     _     _
#  / ___| (_)_ __ | |__ (_)___| |_
# | |   | | | '_ \| '_ \| / __| __|
# | |___| | | |_) | | | | \__ \ |_
#  \____|_|_| .__/|_| |_|_|___/\__|
#           |_|
#

case $1 in
    d)
        cliphist list | rofi -dmenu -replace -config ~/.config/rofi/config-cliphist.rasi | cliphist delete
        ;;

    w)
        if [ $(echo -e "Clear\nCancel" | rofi -dmenu -config ~/.config/rofi/config-short.rasi) == "Clear" ]; then
            cliphist wipe
        fi
        ;;

    *)
        cliphist list | rofi -dmenu -replace -config ~/.config/rofi/config-cliphist.rasi | cliphist decode | wl-copy
        ;;
esac
