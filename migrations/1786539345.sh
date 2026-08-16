echo "Announce process crashes and offer an AI diagnosis"

# Both halves are set up in paths that only run once -- omarchy-provision-user
# exits after finalize-user is marked, and install/user/first-run is skipped
# after the first login -- so existing installs need them done here.

skills_source="$OMARCHY_PATH/default/agents/skills"

if [[ -d $skills_source/diagnose-crash ]]; then
  for skills_dir in ~/.agents/skills ~/.claude/skills ~/.codex/skills ~/.pi/agent/skills; do
    mkdir -p "$skills_dir"
    ln -sfn "$skills_source/diagnose-crash" "$skills_dir/diagnose-crash"
  done
fi

systemctl --user daemon-reload >/dev/null 2>&1 || true

# `systemctl enable` needs a live user manager, which an update from a TTY does
# not have, so fall back to writing the symlink it would have written.
if ! systemctl --user enable omarchy-crash-watch.service >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-crash-watch.service \
    "$wants_dir/omarchy-crash-watch.service"
fi

# Nothing to start into over SSH; the next graphical login handles it. A failed
# start only delays crash toasts, so it stays quiet.
if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start omarchy-crash-watch.service >/dev/null 2>&1 || true
fi
