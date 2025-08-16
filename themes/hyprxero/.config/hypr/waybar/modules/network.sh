#!/usr/bin/env bash

# Detect active interface
INTERFACE=$(ip route | awk '/default/ {print $5}' | head -n1)

# Get interface type
if [[ "$INTERFACE" =~ ^e(n|th) ]]; then
    ICON="󰈀"  # Ethernet
    TYPE="Ethernet"
elif [[ "$INTERFACE" =~ ^w ]]; then
    ICON="󰖩"  # Wi-Fi
    TYPE="Wi-Fi"
else
    ICON="󰖪"  # Unknown/disconnected
    TYPE="Disconnected"
fi

# Get basic info (IP or SSID)
INFO=""

if [[ "$TYPE" == "Wi-Fi" ]]; then
    SSID=$(iw dev "$INTERFACE" link | awk '/SSID:/ {print $2}')
    INFO="SSID: ${SSID:-Disconnected}"
elif [[ "$TYPE" == "Ethernet" ]]; then
    IP=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    INFO="IP: ${IP:-None}"
else
    INFO="No active connection"
fi

# Output JSON for Waybar
echo "{\"text\": \"$ICON\", \"tooltip\": \"$TYPE - $INFO\"}"
