echo "Add sample battery monitor notification hook"

mkdir -p ~/.config/omarchy/hooks

if [[ ! -f ~/.config/omarchy/hooks/battery-monitor.sample ]]; then
  cp "$OMARCHY_PATH/config/omarchy/hooks/battery-monitor.sample" ~/.config/omarchy/hooks/battery-monitor.sample
fi
