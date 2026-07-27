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

first_run_units="$ROOT/install/user/first-run/enable-user-units.sh"
grep -Fx 'systemctl --user daemon-reload' "$first_run_units" >/dev/null
grep -F 'omarchy-sleep-lock.service' "$first_run_units" >/dev/null
pass "first-run reloads and enables the sleep lock service"

upgrade_to_quattro="$ROOT/bin/omarchy-upgrade-to-quattro"
grep -F '6870b232a6c0474b59187882e6d25ae771bba735098bcbedef8a2b73b97e2b6a' "$upgrade_to_quattro" >/dev/null
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
pass "migration notifier only checks once per login"

grep -F 'omarchy-migrate-notify.service' "$first_run_units" >/dev/null ||
  fail "first-run does not enable the login migration notifier"
grep -F 'omarchy-update-user-notify' "$first_run_units" >/dev/null &&
  fail "first-run still enables the retired notifier units"
pass "first-run enables the login-only migration notifier"
