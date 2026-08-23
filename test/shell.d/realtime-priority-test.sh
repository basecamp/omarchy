#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Hyprland calls sched_setscheduler on its event thread and PipeWire's module-rt
# asks for rt.prio 88. Both read RLIMIT_RTPRIO off the systemd user manager,
# which pam_limits fills in from realtime-privileges for members of the realtime
# group -- so the package without the membership leaves both requests failing.
#
# omarchy-base.packages is the list the installer pacstraps; omarchy-other.packages
# only tells the ISO builder which packages to cache in its offline mirror, so a
# package listed only there never reaches a machine.
grep -qxF realtime-privileges "$ROOT/install/omarchy-base.packages" ||
  fail "realtime-privileges is not in the installed package list, so the user manager keeps RLIMIT_RTPRIO=0 and the compositor never gets realtime"

realtime_group_script="$ROOT/install/config/realtime-group.sh"
grep -qE '^grep -qxF realtime "\$provisioning_dir/groups"' "$realtime_group_script" ||
  fail "the realtime group is not recorded for provisioning, so a first-boot user is created without it"
grep -qE '^  usermod -aG realtime' "$realtime_group_script" ||
  fail "an install user that already exists never joins the realtime group"
# realtime is created by the package, not by systemd like input, so a run that
# reaches the usermod without it fails under run_logged and takes the whole
# system setup with it.
grep -qF 'getent group realtime' "$realtime_group_script" ||
  fail "the group grant does not check that realtime exists, so an install without the package aborts on usermod"
grep -qF 'config/realtime-group.sh' "$ROOT/install/config/all.sh" ||
  fail "realtime-group.sh is never run, so nothing grants the group on a fresh install"

# Existing installs have neither the package nor the membership, and no amount
# of updating gets there without a migration that asks for both.
realtime_migration="$ROOT/migrations/1787517200.sh"
[[ -f $realtime_migration ]] ||
  fail "existing installs never gain realtime privileges, so only new installs get a compositor that can ask for it"
grep -qE '^omarchy-pkg-add realtime-privileges' "$realtime_migration" ||
  fail "migration does not install realtime-privileges, so pam_limits has no limits file to read"
grep -qE '^  sudo usermod -aG realtime' "$realtime_migration" ||
  fail "migration does not join the realtime group, so the limits file it just installed applies to nobody"
# `id -nG | grep -qw realtime` also matches a group named pro-realtime, which
# would skip the usermod and then mark the migration done.
grep -qF 'grep -qxF realtime' "$realtime_migration" ||
  fail "migration matches the realtime group loosely, so a similarly named group skips the grant and the marker still lands"
pass "the compositor and audio graph can ask the kernel for realtime, on new and existing installs"

# A libx265 transcode is the one stock workload that must not share a scope with
# the compositor, and it has two entry points: the keybind dispatches a raw exec
# and the menu goes through quickshell, so both sit in session.slice unless uwsm
# hands them to app.slice.
grep -qF 'o.bind("SUPER + CTRL + PERIOD", "Transcode", o.launch("omarchy-transcode"))' \
  "$ROOT/default/hypr/bindings/utilities.lua" ||
  fail "the transcode keybind runs as a compositor child, so a libx265 pass competes with input handling inside the session scope"
grep -qF '"action":"uwsm-app -- omarchy-transcode"' "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "the transcode menu entry runs as a quickshell child, so picking Transcode from the menu still lands the encode in session.slice"
pass "both transcode entry points hand their encode to app.slice"
