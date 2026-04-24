#!/bin/bash

# Fix keyboard backlight brightness stepping for consistent behavior
# See: https://github.com/basecamp/omarchy/issues/5414

echo "Fixing keyboard backlight brightness stepping..."

BACKLIGHT_SCRIPT="$HOME/.local/share/omarchy/bin/omarchy-brightness-keyboard"

# Check if script exists
if [[ ! -f "$BACKLIGHT_SCRIPT" ]]; then
  echo "Keyboard backlight script not found, skipping..."
  exit 0
fi

# Check if it's already the fixed version
if grep -q "num_steps=10" "$BACKLIGHT_SCRIPT"; then
  echo "Keyboard backlight fix already applied"
  exit 0
fi

# Backup the original
cp "$BACKLIGHT_SCRIPT" "${BACKLIGHT_SCRIPT}.bak"

# The fix uses percentage-based stepping instead of +1/-1
# This ensures consistent brightness levels regardless of direction
# New brightness is calculated as: (current_percent rounded to nearest 10%) +/- 10%

cat << 'FIXED_SCRIPT' > "$BACKLIGHT_SCRIPT"
#!/bin/bash

# Adjust keyboard backlight brightness using available steps.
# Usage: omarchy-brightness-keyboard <up|down|cycle>

direction="${1:-up}"

# Find keyboard backlight device (look for *kbd_backlight* pattern in leds class).
device=""
for candidate in /sys/class/leds/*kbd_backlight*; do
  if [[ -e $candidate ]]; then
    device="$(basename "$candidate")"
    break
  fi
done

if [[ -z $device ]]; then
  echo "No keyboard backlight device found" >&2
  exit 1
fi

# Get current and max brightness to determine step size.
max_brightness="$(brightnessctl -d "$device" max)"
current_brightness="$(brightnessctl -d "$device" get)"

# Calculate step as percentage-based to ensure consistent behavior
# Use 10 steps for smooth brightness control (0%, 10%, 20%, ..., 100%)
num_steps=10
step_size=$((max_brightness / num_steps))
[[ $step_size -lt 1 ]] && step_size=1

if [[ $direction == "cycle" ]]; then
  # Cycle through brightness levels: 0 -> 50% -> 100% -> 0
  if [[ $current_brightness -eq 0 ]]; then
    new_brightness=$((max_brightness / 2))
  elif [[ $current_brightness -eq $((max_brightness / 2)) ]]; then
    new_brightness=$max_brightness
  else
    new_brightness=0
  fi
elif [[ $direction == "up" ]]; then
  # Find the next brightness level going up
  # Calculate percentage and round to nearest step
  current_percent=$((current_brightness * 100 / max_brightness))
  next_percent=$(( (current_percent / 10 + 1) * 10 ))
  [[ $next_percent -gt 100 ]] && next_percent=100
  new_brightness=$((max_brightness * next_percent / 100))
  # Ensure we don't stay at the same level
  [[ $new_brightness -le $current_brightness ]] && new_brightness=$((current_brightness + step_size))
  [[ $new_brightness -gt $max_brightness ]] && new_brightness=$max_brightness
else
  # Find the next brightness level going down
  # Calculate percentage and round to nearest step
  current_percent=$((current_brightness * 100 / max_brightness))
  next_percent=$(( (current_percent + 5) / 10 * 10 ))
  # Ensure we go to a different level
  [[ $next_percent -ge $current_percent ]] && [[ $current_percent -gt 0 ]] && next_percent=$((next_percent - 10))
  [[ $next_percent -lt 0 ]] && next_percent=0
  new_brightness=$((max_brightness * next_percent / 100))
  # Ensure we don't stay at the same level
  [[ $new_brightness -ge $current_brightness ]] && new_brightness=$((current_brightness - step_size))
  [[ $new_brightness -lt 0 ]] && new_brightness=0
fi

# Ensure we end up at a valid brightness level
[[ $new_brightness -lt 0 ]] && new_brightness=0
[[ $new_brightness -gt $max_brightness ]] && new_brightness=$max_brightness

# Set the new brightness.
brightnessctl -d "$device" set "$new_brightness" >/dev/null

# Use SwayOSD to display the new brightness setting.
percent=$((new_brightness * 100 / max_brightness))
omarchy-swayosd-kbd-brightness "$percent"
FIXED_SCRIPT

chmod +x "$BACKLIGHT_SCRIPT"

echo "Keyboard backlight brightness fix applied!"
echo "Brightness will now use consistent percentage steps: 0%, 10%, 20%, ..., 100%"
