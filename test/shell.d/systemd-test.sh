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

notify_path="$ROOT/default/systemd/user/omarchy-update-user-notify.path"
! grep -q 'PathExistsGlob' "$notify_path"
grep -Fx 'PathModified=/usr/share/omarchy/migrations' "$notify_path" >/dev/null
pass "migration watcher is edge-triggered so applied migrations on disk cannot re-trigger it"

notify_service="$ROOT/default/systemd/user/omarchy-update-user-notify.service"
! grep -q 'StartLimit' "$notify_service"
grep -Fx 'WantedBy=graphical-session.target' "$notify_service" >/dev/null
pass "migration notifier keeps its start-rate limit and still runs once per login"
