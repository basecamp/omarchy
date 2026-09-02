echo "Scale fcitx5's candidate window for XWayland apps on HiDPI displays"

# The fcitx5 unit now publishes Xft.dpi to XWayland before it starts. Reload so
# the next login runs the new ExecStartPre, and repair the running session
# directly: fcitx5 re-reads the property the moment it changes, so no restart.
systemctl --user daemon-reload >/dev/null 2>&1 || true
if [[ -n ${DISPLAY:-} ]]; then
  omarchy-hyprland-xwayland-dpi >/dev/null 2>&1 || true
fi
