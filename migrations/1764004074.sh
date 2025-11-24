echo "Install kernel-modules-hook"

omarchy-pkg-add kernel-modules-hook
sudo systemctl enable --now linux-modules-cleanup.service
