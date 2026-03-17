#!/bin/bash

# Returns the battery percentage remaining as an integer.
# Used by the battery monitor and the Ctrl + Shift + Super + B hotkey.

upower -i $(upower -e | grep BAT) | awk '/percentage/ { 
    print int($2)
    exit
}'
