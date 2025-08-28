#!/bin/sh

action=$1

active_class=$(hyprctl activewindow -j | jq -r '.class')

case "$action" in
    copy)
        key="C"
        ;;
    paste)
        key="V"
        ;;
    cut)
        key="X"
        ;;
esac

# Check if active window is a terminal by matching common terminal classes
is_terminal() {
    case "$active_class" in
        *alacritty*|*kitty*|*konsole*|*gnome-terminal*|*xterm*|*wezterm*|*foot*|*st|*urxvt*|*rxvt*|*tilix*|*terminator*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

if is_terminal; then
    shortcut="CTRL_SHIFT,$key,"
else
    shortcut="CTRL,$key,"
fi

hyprctl dispatch sendshortcut "$shortcut"