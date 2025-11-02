#!/bin/bash

LIST_FILE="$HOME/.local/state/omarchy/minimized_windows.list"

# Check if the list file exists and is non-empty
if [ ! -f "$LIST_FILE" ] || [ ! -s "$LIST_FILE" ]; then
    # No minimized windows - return empty text (waybar will hide it)
    echo '{"text": ""}'
    exit 0
fi

# Clean up list file - remove windows that are not actually on minimized workspace
ALL_CLIENTS=$(hyprctl clients -j 2>/dev/null)
if [ -n "$ALL_CLIENTS" ]; then
    CLEANED_LIST=""
    while IFS=$'\t' read -r ADDRESS TITLE CLASS; do
        # Check if window exists and is on the minimized workspace
        WINDOW_WS=$(echo "$ALL_CLIENTS" | jq -r --arg addr "$ADDRESS" '.[] | select(.address == $addr) | .workspace.name' 2>/dev/null)
        if [[ "$WINDOW_WS" == "special:minimized" ]]; then
            CLEANED_LIST="${CLEANED_LIST}${ADDRESS}\t${TITLE}\t${CLASS}\n"
        fi
    done < "$LIST_FILE"
    
    # Update the list file if we cleaned anything
    if [ -n "$CLEANED_LIST" ]; then
        echo -ne "$CLEANED_LIST" > "$LIST_FILE"
    else
        # No valid windows left, clear the file
        > "$LIST_FILE"
        echo '{"text": ""}'
        exit 0
    fi
fi

# Count the number of minimized windows
COUNT=$(wc -l < "$LIST_FILE" 2>/dev/null | tr -d ' ')

# Generate JSON output for Waybar
if [ "$COUNT" -gt 0 ]; then
    echo "{\"text\":\"󰘸 $COUNT\",\"class\":\"has-windows\",\"tooltip\":\"$COUNT Minimized Window$([ $COUNT -ne 1 ] && echo 's')\"}"
else
    echo '{"text": ""}'
fi

