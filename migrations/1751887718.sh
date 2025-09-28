echo "Install Impala as new wifi selection TUI"

if omarchy-cmd-missing impala; then
  omarchy-pkg-add impala
  omarchy-refresh-waybar
fi
