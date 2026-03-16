echo "Replace Impala with nettui for Omarchy network controls"

if omarchy-cmd-missing nettui; then
  omarchy-pkg-add nettui
fi

if omarchy-cmd-present impala; then
  omarchy-pkg-drop impala
fi
