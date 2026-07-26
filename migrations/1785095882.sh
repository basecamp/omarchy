echo "Only check for pending migrations at login, not on every package update"

# omarchy-update-user-notify.path watched /usr/share/omarchy/migrations, but
# pacman writes that directory during every update -- including the blessed
# `omarchy update`, which runs omarchy-migrate a step later. The watcher fired a
# critical notification for migrations that were already being applied in the
# visible update terminal. Retire the watcher and keep only the once-per-login
# check, now named after the command it runs.

wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"

systemctl --user daemon-reload >/dev/null 2>&1 || true

# The watcher's unit file is already gone, but it stays loaded in a session that
# started before this update, so stop it before it can fire again.
systemctl --user stop omarchy-update-user-notify.path >/dev/null 2>&1 || true

# Enable the replacement before dropping the old enablement, so a failure here
# can never leave a user with no notifier at all. Enable without --now: this
# usually runs from inside `omarchy update`, and starting the notifier here would
# pop a toast for the migrations running right after it -- the exact behavior
# being removed. `systemctl enable` also needs a live user manager, which
# `omarchy update` over SSH does not have, so fall back to writing precisely the
# symlink it would have written rather than silently doing nothing.
if ! systemctl --user enable omarchy-migrate-notify.service >/dev/null 2>&1; then
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-migrate-notify.service \
    "$wants_dir/omarchy-migrate-notify.service"
fi

# Drop the retired enablement by hand instead of through `systemctl disable`.
# The package ships omarchy-update-user-notify.service as a compatibility
# symlink onto the new unit, for users who have not reached this migration yet,
# so disabling that name here would disable the replacement along with it.
rm -f "$wants_dir/omarchy-update-user-notify.path" \
  "$wants_dir/omarchy-update-user-notify.service"

systemctl --user reset-failed omarchy-update-user-notify.path >/dev/null 2>&1 || true
systemctl --user daemon-reload >/dev/null 2>&1 || true
