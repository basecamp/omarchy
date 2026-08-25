#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const nightlight = requireFromRoot('shell/plugins/services/nightlight/NightlightModel.js')

assertEqual(nightlight.temperatureFromOutput('4000\n'), 4000, 'nightlight parses probe temperature')
assertEqual(nightlight.temperatureFromOutput("Couldn't connect to hyprsunset"), null, 'nightlight treats unreachable hyprsunset as unknown')
assertEqual(nightlight.isNightlight(4000), true, 'nightlight reports warm temperatures as enabled')
assertEqual(nightlight.isNightlight(5999), true, 'nightlight reports warmer-than-identity values as enabled')
assertEqual(nightlight.isNightlight(6000), false, 'nightlight reports identity temperature as disabled')
assertEqual(nightlight.isNightlight(null), false, 'nightlight reports unknown temperature as disabled')
JS

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"
STATE="$TMPDIR/hyprsunset-temp"
SHELL_LOG="$TMPDIR/omarchy-shell-log"

cat >"$TMPDIR/bin/hyprctl" <<'SH'
#!/bin/bash

if [[ ${1:-} == "hyprsunset" && ${2:-} == "temperature" ]]; then
  if [[ -n ${3:-} ]]; then
    printf '%s\n' "$3" >"$HYPRSUNSET_STATE"
  else
    cat "$HYPRSUNSET_STATE" 2>/dev/null || exit 1
  fi
  exit 0
fi

exit 1
SH

cat >"$TMPDIR/bin/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_SHELL_LOG"
SH

# Stubbed, or the suite would start a real hyprsunset on the dev machine.
cat >"$TMPDIR/bin/systemctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
SH

chmod +x "$TMPDIR/bin/hyprctl" "$TMPDIR/bin/omarchy-shell" "$TMPDIR/bin/systemctl"

SYSTEMCTL_LOG="$TMPDIR/systemctl-log"
FAKE_HOME="$TMPDIR/home"
FLAG="$FAKE_HOME/.local/state/omarchy/toggles/nightlight"

# $ROOT/bin on PATH so omarchy-toggle and omarchy-toggle-enabled are the repo's
# own, not whatever version is installed on the machine running the suite.
nightlight_cli() {
  PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
  HOME="$FAKE_HOME" \
  HYPRSUNSET_STATE="$STATE" \
  OMARCHY_SHELL_LOG="$SHELL_LOG" \
  SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
    "$ROOT/bin/omarchy-toggle-nightlight" "$@"
}

nightlight_status() {
  printf '%s\n' "$1" >"$STATE"
  nightlight_cli --status
}

[[ $(nightlight_status 4000 | jq -r .enabled) == "true" ]] || fail "nightlight status reports 4000K as enabled"
pass "nightlight status reports 4000K as enabled"

[[ $(nightlight_status 5999 | jq -r .enabled) == "true" ]] || fail "nightlight status reports warmer-than-identity values as enabled"
pass "nightlight status reports warmer-than-identity values as enabled"

[[ $(nightlight_status 6000 | jq -r .enabled) == "false" ]] || fail "nightlight status reports identity temperature as disabled"
pass "nightlight status reports identity temperature as disabled"

[[ $(nightlight_status 6500 | jq -r .enabled) == "false" ]] || fail "nightlight status reports daylight temperature as disabled"
pass "nightlight status reports daylight temperature as disabled"

printf '6500\n' >"$STATE"
: >"$SHELL_LOG"
nightlight_cli >/dev/null
[[ $(<"$STATE") == 4000 ]] || fail "nightlight toggle warms the screen from daylight"
pass "nightlight toggle warms the screen from daylight"

grep -Fqx -- '-q nightlight refresh' "$SHELL_LOG" || fail "nightlight toggle nudges the shell nightlight service"
pass "nightlight toggle nudges the shell nightlight service"

nightlight_cli >/dev/null
[[ $(<"$STATE") == 6500 ]] || fail "nightlight toggle restores daylight from night light"
pass "nightlight toggle restores daylight from night light"

if rg -q 'omarchy.indicators' "$ROOT/bin/omarchy-toggle-nightlight"; then
  fail "nightlight toggle leaves indicator refresh to the nightlight service"
fi
pass "nightlight toggle leaves indicator refresh to the nightlight service"

# hyprsunset has to come back on its own after a crash: a monitor hotplug
# disconnects every Wayland client with a bind in flight and takes it with them.
# An unsupervised copy left night light off for the rest of the session.

printf '6500\n' >"$STATE"
: >"$SYSTEMCTL_LOG"
nightlight_cli on >/dev/null
[[ $(<"$STATE") == 4000 ]] || fail "nightlight accepts an explicit on"
pass "nightlight accepts an explicit on"

grep -Fqx -- '--user start --no-block hyprsunset.service' "$SYSTEMCTL_LOG" ||
  fail "nightlight starts hyprsunset through its systemd user service"
pass "nightlight starts hyprsunset through its systemd user service"

[[ -f $FLAG ]] || fail "nightlight records the toggle so a restart can restore it"
pass "nightlight records the toggle so a restart can restore it"

nightlight_cli off >/dev/null
[[ $(<"$STATE") == 6500 ]] || fail "nightlight accepts an explicit off"
pass "nightlight accepts an explicit off"

[[ -f $FLAG ]] && fail "nightlight clears the record when switched off"
pass "nightlight clears the record when switched off"

# What the service's ExecStartPost runs. hyprsunset re-reads its config on every
# start, and Omarchy ships an identity profile, so a restart returns neutral.
nightlight_cli on >/dev/null
printf '6500\n' >"$STATE"
: >"$SYSTEMCTL_LOG"
nightlight_cli --apply >/dev/null
[[ $(<"$STATE") == 4000 ]] || fail "nightlight re-applies the tint a restarted hyprsunset came back without"
pass "nightlight re-applies the tint a restarted hyprsunset came back without"

[[ -s $SYSTEMCTL_LOG ]] && fail "nightlight re-apply never starts the unit it runs inside"
pass "nightlight re-apply never starts the unit it runs inside"

# With night light off, hyprsunset.conf is the standing intent. Forcing a
# temperature here would stomp the scheduled profiles the manual points at.
nightlight_cli off >/dev/null
printf '4000\n' >"$STATE"
nightlight_cli --apply >/dev/null
[[ $(<"$STATE") == 4000 ]] || fail "nightlight re-apply leaves a scheduled profile alone when switched off"
pass "nightlight re-apply leaves a scheduled profile alone when switched off"

# Comments stripped first: these files explain in prose why they no longer reach
# for uwsm-app, and the guard is about what they run, not what they mention.
for path in bin/omarchy-toggle-nightlight bin/omarchy-restart-hyprsunset \
  shell/plugins/services/nightlight/Service.qml; do
  if rg -N --invert-match '^\s*(#|//)' "$ROOT/$path" | rg -q 'uwsm-app'; then
    fail "$path leaves starting hyprsunset to its systemd user service"
  fi
done
pass "nightlight never starts an unsupervised hyprsunset"

rg -q 'ExecStartPost=-/usr/bin/omarchy-toggle-nightlight --apply' \
  "$ROOT/default/systemd/user/hyprsunset.service.d/10-omarchy.conf" ||
  fail "hyprsunset drop-in re-applies the temperature after a restart"
pass "hyprsunset drop-in re-applies the temperature after a restart"
