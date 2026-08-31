echo "Install playerctl for existing Voxtype installs"

omarchy-pkg-present voxtype-bin || exit 0
omarchy-pkg-add playerctl
