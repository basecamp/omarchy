echo "Hide limine-snapper-restore from app launcher"

mkdir -p ~/.local/share/applications
cp "$OMARCHY_PATH/applications/hidden/limine-snapper-restore.desktop" ~/.local/share/applications/
