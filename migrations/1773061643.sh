echo "Add battery monitor hooks"

if [[ ! -d ~/.config/omarchy/hooks/battery-monitor.d ]]; then
  mkdir -p ~/.config/omarchy/hooks/battery-monitor.d
  cp -r "$OMARCHY_PATH/config/omarchy/hooks/battery-monitor.d/." ~/.config/omarchy/hooks/battery-monitor.d
fi
