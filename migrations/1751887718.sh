echo "Install Impala as new wifi selection TUI"

if cmd-missing impala; then
  pkg-add impala
  omarchy-refresh-waybar
fi
