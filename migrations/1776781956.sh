echo "Dell XPS Panther Lake display kernel cmdline is no longer necessary"

DROP_IN="/etc/limine-entry-tool.d/dell-xps-ptl-display.conf"
DEFAULT_LIMINE="/etc/default/limine"
NEEDS_UPDATE=0

if [[ -f $DROP_IN ]]; then
  sudo rm -f "$DROP_IN"
  NEEDS_UPDATE=1
fi

if [[ -f $DEFAULT_LIMINE ]] && grep -q 'xe\.enable_psr' "$DEFAULT_LIMINE"; then
  sudo sed -i -E '/^KERNEL_CMDLINE.*xe\.enable_psr/d; /^# .*(Dell XPS|Xe PSR|Panel Replay)/d' "$DEFAULT_LIMINE"
  NEEDS_UPDATE=1
fi

if (( NEEDS_UPDATE )); then
  sudo limine-update
fi
