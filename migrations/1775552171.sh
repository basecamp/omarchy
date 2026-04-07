echo "Add CSS override for Walker"

# If the existing CSS override file doesn't already exist, add it.
if [[ ! -e ~/.config/walker/style.css ]]; then
  cp $OMARCHY_PATH/config/walker/style.css ~/.config/walker/style.css
fi
