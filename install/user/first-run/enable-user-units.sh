#!/bin/bash

# Enable AND start the user systemd units we ship. Runs at first-run rather
# than at finalize-user time because the user manager isn't live during the
# ISO chroot — by first-run, the Hyprland/uwsm session is up and
# `systemctl --user enable --now` both writes the correct .wants symlinks
# (based on each unit's [Install]/WantedBy) and starts the services so the
# first session has bluetooth pairing, sleep lock, etc. live immediately
# instead of waiting for the next login. ConditionPath* in the unit files
# keep the enabled units inert on hardware they don't apply to.

set -euo pipefail

# The settings package lists user units explicitly. Until it ships this one
# to /usr/lib/systemd/user, stage it from the omarchy tree so enable --now
# can find it. Prefer the packaged copy once it exists.
stage_user_unit() {
  local name=$1
  local src="$OMARCHY_PATH/default/systemd/user/$name"
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local staged="$config_home/systemd/user/$name"
  if [[ -f /usr/lib/systemd/user/$name ]]; then
    if [[ -f $staged ]] && cmp -s "$staged" "/usr/lib/systemd/user/$name"; then
      rm -f "$staged"
    fi
    return 0
  fi

  [[ -f $src ]] || return 0
  # first-run reruns with --force, so never clobber a copy already there.
  [[ -f $staged ]] && return 0

  install -Dm644 "$src" "$staged"
}

stage_user_unit omarchy-wifi-recover.service

systemctl --user daemon-reload
systemctl --user enable --now \
  bt-agent.service \
  omarchy-recover-internal-monitor.service \
  omarchy-sleep-lock.service \
  omarchy-migrate-notify.service \
  omarchy-fcitx5.service \
  omarchy-crash-watch.service \
  omarchy-wifi-recover.service
