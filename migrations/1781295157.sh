echo "Apply the GSK_RENDERER fix to the autostarted Walker service"

mkdir -p ~/.config/autostart/
cp $OMARCHY_PATH/default/walker/walker.desktop ~/.config/autostart/
systemctl --user daemon-reload
omarchy-restart-walker
