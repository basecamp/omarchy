echo "Fix screensaver to cover popped windows"

SCREENSAVER_SCRIPT=~/.local/share/omarchy/bin/omarchy-launch-screensaver

# Skip if already patched
if grep -q "Temporarily unpin all popped windows" "$SCREENSAVER_SCRIPT" 2>/dev/null; then
  exit 0
fi

# Only patch if the file exists and has the expected structure
if [[ -f "$SCREENSAVER_SCRIPT" ]] && grep -q 'focused=$(hyprctl monitors' "$SCREENSAVER_SCRIPT"; then
  # Insert unpinning logic before the focused monitor line using sed
  sed -i '/focused=$(hyprctl monitors/i\
# Temporarily unpin all popped windows so screensaver covers them\
popped_windows=$(hyprctl clients -j | jq -r '\''.[] | select(.tags[] == "pop") | .address'\'')\
if [[ -n "$popped_windows" ]]; then\
  while IFS= read -r addr; do\
    hyprctl dispatch pin address:"$addr"\
  done <<< "$popped_windows"\
fi\
' "$SCREENSAVER_SCRIPT"
fi
