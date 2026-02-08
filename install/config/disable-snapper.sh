# Disable snapper services (not used in this fork)
sudo systemctl disable --now limine-snapper-sync.service 2>/dev/null || true
sudo systemctl disable --now snapper-timeline.timer 2>/dev/null || true
sudo systemctl disable --now snapper-cleanup.timer 2>/dev/null || true
