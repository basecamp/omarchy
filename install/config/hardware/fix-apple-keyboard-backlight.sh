#!/bin/bash
# Set Apple keyboard backlight to 100% on supported MacBooks
# This runs during installation (via all.sh) to ensure the keyboard backlight
# is visible, since touchbar/physical backlight keys may not work without
# additional drivers

find_kbd_backlight() {
    local device
    for pattern in ":white:kbd_backlight" "sms::kbd_backlight" ".*::kbd_backlight"; do
        device=$(brightnessctl -l 2>/dev/null | grep -oP "Device '\\K[^']*$pattern[^']*" | head -1)
        if [[ -n "$device" ]]; then
            echo "$device"
            return 0
        fi
    done
    return 1
}

if [[ -f /sys/class/dmi/id/sys_vendor ]] && grep -qi "Apple" /sys/class/dmi/id/sys_vendor; then
    device=$(find_kbd_backlight)
    if [[ -n "$device" ]]; then
        echo "Detected Apple hardware, setting keyboard backlight to 100% (device: $device)"
        brightnessctl -d "$device" set 100% &>/dev/null
    fi
fi
