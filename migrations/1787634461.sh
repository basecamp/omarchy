echo "Supervise hyprsunset so night light can't silently die"

# hyprsunset was started fire-and-forget, from the nightlight toggle and from
# the shell's nightlight service. Nothing restarted it and nothing noticed when
# it went away, so one death left the screen cold for the rest of the session.
# A monitor hotplug is enough to cause it: destroying a wl_output global
# disconnects every client with a bind still in flight, and hyprsunset aborts
# along with the browser and the shell.
#
# It runs through hyprsunset.service now, which the hyprsunset package ships
# with Restart=on-failure, plus an Omarchy drop-in that re-applies the
# temperature the daemon comes back without.

user_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
autostart="$user_config_home/hypr/autostart.lua"

systemctl --user daemon-reload >/dev/null 2>&1 || true

# The manual used to point schedule users at an autostart line. That copy is
# unsupervised and would also fight the unit's, so retire it and enable the unit
# for exactly the users who had it -- night light is off by default, and nobody
# else should gain a daemon at login from this. Anchored past any `--`, so a line
# someone had already commented out is left alone rather than read as intent.
scheduled=0
pattern='^[[:space:]]*o\.launch_on_start\("hyprsunset"\)'
if [[ -f $autostart ]] && grep -Eq "$pattern" "$autostart"; then
  scheduled=1
  sed -Ei "\\|$pattern|d" "$autostart"
fi

if ((scheduled)); then
  # Enable without --now; the start below is conditional on there being a
  # session to start into. `systemctl enable` needs a live user manager, which
  # an `omarchy update` from a TTY does not have, so fall back to writing
  # exactly the symlink it would have written rather than leaving this unenabled.
  if ! systemctl --user enable hyprsunset.service >/dev/null 2>&1; then
    wants_dir="$user_config_home/systemd/user/graphical-session.target.wants"
    mkdir -p "$wants_dir"
    ln -sfn /usr/lib/systemd/user/hyprsunset.service \
      "$wants_dir/hyprsunset.service"
  fi
fi

# Outside a graphical session -- an update over SSH -- there is nothing to hand
# over: no stray hyprsunset to replace, and the unit's own ConditionEnvironment
# would skip the start anyway. Any enablement above is the whole job.
systemctl --user is-active --quiet graphical-session.target || exit 0

# Nothing running means nothing to migrate. Don't start one: night light is a
# toggle, and this migration is not the user asking for it.
pgrep -x hyprsunset >/dev/null || exit 0

# Already under the unit from an earlier run of this migration.
systemctl --user is-active --quiet hyprsunset.service && exit 0

# Carry the current temperature across the handover. The flag is new, so a
# hyprsunset holding night light right now has nothing recording that yet, and
# the drop-in's re-apply would bring it back neutral.
temperature=$(hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' | head -n1)
if [[ -n $temperature ]] && ((temperature < 6000)); then
  omarchy-toggle nightlight on
fi

# The two can't coexist: a second hyprsunset fails to bind the socket the first
# owns, and Restart=on-failure would turn that into a restart loop.
pkill -x hyprsunset >/dev/null 2>&1 || true

# Report what systemctl actually said. This kills a hyprsunset that was working
# a moment ago, so a start failure has to be loud rather than leaving the screen
# stuck and the migration marked complete.
if ! error=$(systemctl --user start hyprsunset.service 2>&1); then
  echo "Could not start hyprsunset.service: $error"
  echo "Night light will not work until the next login."
fi
