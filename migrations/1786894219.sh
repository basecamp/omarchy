echo "Restart the crash watcher so it picks up the inotify rewrite"

# omarchy-crash-watch followed the journal with journalctl -f, mapping the
# whole journal into memory; the rewrite watches the systemd-coredump
# directory with inotify instead, at a few MB. pacman replaces the script on
# update, but the running service keeps the old one in memory until it
# restarts, so restart it here for the memory win to land during the update
# instead of at the next login.

# The unit's ConditionPathExists re-checks the same toggle flag at every
# start, so a watcher the user disabled stays off: honoring the flag here
# makes this migration a no-op for them. Only nudge a watcher that is
# actually running; a stopped one stays stopped.
[[ -f "$HOME/.local/state/omarchy/toggles/crash-capture-off" ]] && exit 0

systemctl --user is-active omarchy-crash-watch.service >/dev/null 2>&1 &&
  systemctl --user restart omarchy-crash-watch.service >/dev/null 2>&1 || true
