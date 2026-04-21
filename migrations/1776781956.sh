echo "Dell XPS Panther Lake display kernel cmdline drop-in is no longer necessary"

DROP_IN="/etc/limine-entry-tool.d/dell-xps-ptl-display.conf"

if [[ -f $DROP_IN ]]; then
  sudo rm -f "$DROP_IN"
  sudo limine-update
fi
