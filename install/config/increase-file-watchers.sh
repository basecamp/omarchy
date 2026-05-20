# etc/sysctl.d/90-omarchy-file-watchers.conf ships via omarchy-settings.
# Apply the new sysctl values immediately.
sudo sysctl --system >/dev/null 2>&1
