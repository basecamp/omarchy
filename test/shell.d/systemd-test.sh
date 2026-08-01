#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

service="$ROOT/default/systemd/user/bt-agent.service"

grep -Fx 'ExecCondition=/usr/bin/systemctl is-active --quiet bluetooth.service' "$service" >/dev/null
pass "bt-agent skips when bluetooth.service is inactive"

grep -Fx 'Restart=on-failure' "$service" >/dev/null
pass "bt-agent still restarts after runtime failures"

sleep_service="$ROOT/default/systemd/user/omarchy-sleep-lock.service"
grep -Fx 'ExecStart=/usr/bin/omarchy-system-sleep-monitor' "$sleep_service" >/dev/null
pass "sleep lock service uses the package-backed monitor path"

grep -Fx 'After=dbus.socket wayland-session-waitenv.service' "$sleep_service" >/dev/null ||
  fail "sleep lock monitor starts before UWSM imports the graphical session environment"
grep -Fx 'PartOf=graphical-session.target' "$sleep_service" >/dev/null ||
  fail "sleep lock monitor survives logout with a stale Wayland environment"
grep -Fx 'ConditionEnvironment=OMARCHY_PATH' "$sleep_service" >/dev/null ||
  fail "sleep lock monitor can start without the Omarchy shell path"
grep -Fx 'ConditionEnvironment=WAYLAND_DISPLAY' "$sleep_service" >/dev/null ||
  fail "sleep lock monitor can start without a Wayland display"
pass "sleep lock service follows the initialized graphical session"

first_run_units="$ROOT/install/user/first-run/enable-user-units.sh"
grep -Fx 'systemctl --user daemon-reload' "$first_run_units" >/dev/null
grep -F 'omarchy-sleep-lock.service' "$first_run_units" >/dev/null
pass "first-run reloads and enables the sleep lock service"

upgrade_to_quattro="$ROOT/bin/omarchy-upgrade-to-quattro"
grep -F '6870b232a6c0474b59187882e6d25ae771bba735098bcbedef8a2b73b97e2b6a' "$upgrade_to_quattro" >/dev/null
grep -F 'bcd1a76cb5c63514922bc5e11af22ae480fc6d06a99863364e02bdf3c7bdceaf' "$upgrade_to_quattro" >/dev/null
grep -F 'ExecStart=%h/.local/share/omarchy/bin/omarchy-system-sleep-monitor' "$upgrade_to_quattro" >/dev/null
grep -F 'ExecStart=/usr/bin/omarchy-system-sleep-monitor' "$upgrade_to_quattro" >/dev/null
grep -F 'reset-failed omarchy-sleep-lock.service' "$upgrade_to_quattro" >/dev/null
pass "Omarchy 4 upgrade repairs the legacy sleep lock unit path"

[[ -e $ROOT/default/systemd/user/omarchy-update-user-notify.path ]] &&
  fail "the retired migration watcher is back; pacman writing the migration directory during omarchy update would notify about migrations that update is already applying"
grep -rlE '^(Path[A-Za-z]+|DirectoryNotEmpty)=.*/usr/share/omarchy/migrations' "$ROOT/default/systemd/user" >/dev/null 2>&1 &&
  fail "a user unit watches the migration directory again; the notifier must stay login-only"
pass "no unit watches the migration directory, so package updates cannot trigger the notifier"

notify_service="$ROOT/default/systemd/user/omarchy-migrate-notify.service"
grep -Fx 'ExecStart=/usr/bin/omarchy-migrate-notify' "$notify_service" >/dev/null
grep -Fx 'WantedBy=graphical-session.target' "$notify_service" >/dev/null
grep -Fx 'After=graphical-session.target' "$notify_service" >/dev/null ||
  fail "migration notifier can deadlock UWSM by blocking graphical-session.target"
pass "migration notifier checks once per login after the graphical session is ready"

grep -F 'omarchy-migrate-notify.service' "$first_run_units" >/dev/null ||
  fail "first-run does not enable the login migration notifier"
grep -F 'omarchy-update-user-notify' "$first_run_units" >/dev/null &&
  fail "first-run still enables the retired notifier units"
pass "first-run enables the login-only migration notifier"

fcitx_service="$ROOT/default/systemd/user/omarchy-fcitx5.service"
grep -Fx 'ExecStart=/usr/bin/fcitx5 --disable notificationitem' "$fcitx_service" >/dev/null
grep -Fx 'Restart=always' "$fcitx_service" >/dev/null ||
  fail "fcitx5 exits 0 on a duplicate bus name, so on-failure would leave the user with no input method"
grep -Fx 'After=graphical-session.target' "$fcitx_service" >/dev/null ||
  fail "fcitx5 needs WAYLAND_DISPLAY, which uwsm imports before it reaches graphical-session.target"
grep -Fx 'PartOf=graphical-session.target' "$fcitx_service" >/dev/null ||
  fail "fcitx5 must stop with the compositor instead of lingering against a dead wayland socket"
grep -Fx 'WantedBy=graphical-session.target' "$fcitx_service" >/dev/null ||
  fail "fcitx5 is never pulled in at login without a WantedBy"
grep -Fx 'ConditionEnvironment=WAYLAND_DISPLAY' "$fcitx_service" >/dev/null ||
  fail "an update over SSH has a live user manager and no display; starting fcitx5 there wedges the unit active-but-blind, and Wants= will not replace it at graphical login"

fcitx_migration="$ROOT/migrations/1785167800.sh"
grep -F 'is-active --quiet graphical-session.target' "$fcitx_migration" >/dev/null ||
  fail "migration kills fcitx5 and starts the unit outside a graphical session"
grep -F 'systemctl --user enable omarchy-fcitx5.service' "$fcitx_migration" >/dev/null ||
  fail "migration must enable without --now; --now starts the unit before the session-gate check"
grep -F 'Could not start omarchy-fcitx5.service' "$fcitx_migration" >/dev/null ||
  fail "migration pkills a working fcitx5, so a failed handover must be reported instead of marked complete"

grep -F 'pkill -x fcitx5' "$ROOT/bin/omarchy-restart-xcompose" >/dev/null ||
  fail "restart-xcompose cannot reload a fcitx5 running outside the unit, so it silently keeps serving the old table"

grep -F 'omarchy-fcitx5.service' "$first_run_units" >/dev/null ||
  fail "first-run does not enable the input method, so ~/.XCompose sequences never resolve"
grep -F 'fcitx5' "$ROOT/default/hypr/autostart.lua" >/dev/null &&
  fail "fcitx5 is autostarted from Hyprland; an unsupervised launch dies silently and takes every compose sequence with it"
pass "fcitx5 runs supervised, so a lost input method comes back instead of killing XCompose until logout"

oomd_slice="$ROOT/default/systemd/user/app.slice.d/10-oomd.conf"
grep -Fx 'ManagedOOMMemoryPressure=kill' "$oomd_slice" >/dev/null ||
  fail "nothing is a kill candidate, so systemd-oomd watches the machine thrash and never acts"
grep -Fx 'ManagedOOMSwap=kill' "$oomd_slice" >/dev/null ||
  fail "no swap backstop for the slower shape of the same failure"

# Hyprland lives in session.slice/wayland-wm@hyprland.desktop.service. Marking
# any ancestor of that as a kill candidate puts the compositor back in the
# victim pool, which is the crash this whole thing exists to prevent.
candidates=$(grep -rlE '^ManagedOOM(MemoryPressure|Swap)=kill' "$ROOT/default/systemd" "$ROOT/etc/systemd" 2>/dev/null || true)
[[ $candidates == "$oomd_slice" ]] ||
  fail "systemd-oomd kill candidacy is set outside app.slice, which can select the compositor: $candidates"
pass "only user app scopes are systemd-oomd kill candidates"

oomd_conf="$ROOT/etc/systemd/oomd.conf.d/10-omarchy.conf"
grep -Fx 'DefaultMemoryPressureLimit=50%' "$oomd_conf" >/dev/null ||
  fail "no pressure limit; the 60% default rides thrashing longer than a desktop stays usable"
grep -Fx 'DefaultMemoryPressureDurationSec=20s' "$oomd_conf" >/dev/null ||
  fail "no pressure duration set for the tightened limit"
pass "systemd-oomd acts on sustained memory stall"

grep -Fx 'systemctl enable systemd-oomd.service' "$ROOT/install/config/enable-services.sh" >/dev/null ||
  fail "new installs ship the oomd drop-ins with the daemon that reads them disabled"

oomd_migration=$(grep -rl 'systemd-oomd.service' "$ROOT/migrations" | head -n 1 || true)
[[ -n $oomd_migration ]] ||
  fail "existing installs never enable systemd-oomd; enable-services.sh only runs at install time"
grep -F 'systemctl --user daemon-reload' "$oomd_migration" >/dev/null ||
  fail "migration leaves the user manager unaware of app.slice candidacy until the next login"
pass "existing installs enable systemd-oomd and report app.slice without a relogin"
