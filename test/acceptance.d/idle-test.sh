#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

config="$HOME/.config/omarchy/shell.json"
backup="$ARTIFACTS/shell.json.orig"

[[ -f $config ]] || fail "shell.json exists to configure idle timings"
cp "$config" "$backup"

restore_config() {
  cp "$backup" "$config"
  omarchy-shell -q shell reloadConfig >/dev/null 2>&1 || true
  hyprctl dispatch closewindow "class:^(org\.omarchy\.screensaver)$" >/dev/null 2>&1 || true
}
trap restore_config EXIT

set_idle() {
  local screensaver="$1" lock="$2"

  jq --argjson screensaver "$screensaver" --argjson lock "$lock" \
    '.idle = {screensaver: $screensaver, lock: $lock}' "$backup" >"$config.tmp"
  mv "$config.tmp" "$config"
  omarchy-shell shell reloadConfig >/dev/null
}

idle_status() {
  omarchy-shell idle status
}

idle_field() {
  idle_status | jq -r "$1"
}

idle_field_is() {
  [[ $(idle_field "$1") == "$2" ]]
}

# The three spellings of "off" that used to parse as 0 -- which meant "fire the
# moment the session goes idle", the most hostile reading of the user's intent.
for spelling in false null '"off"'; do
  set_idle 150 "$spelling"

  wait_until "a lock disabled with $spelling is reported as unconfigured" 15 idle_field_is '.lockConfigured' false
  [[ $(idle_field '.lock') == "-1" ]] ||
    fail "a lock disabled with $spelling reports the disabled sentinel" "$(idle_status)"
  pass "a lock disabled with $spelling reports the disabled sentinel"

  # A disabled lock must not take the screensaver down with it.
  idle_field_is '.screensaverConfigured' true ||
    fail "a lock disabled with $spelling leaves the screensaver configured" "$(idle_status)"
  pass "a lock disabled with $spelling leaves the screensaver configured"
done

# Timings are clamped to the signed 32-bit millisecond ceiling of the Timer
# behind them; past it the interval wraps and fires immediately.
set_idle 150 999999999
wait_until "an oversized lock clamps to the timer ceiling" 15 idle_field_is '.lock' 2147483

# An omitted timing still falls back to its default rather than disabling.
jq 'del(.idle)' "$backup" >"$config.tmp" && mv "$config.tmp" "$config"
omarchy-shell shell reloadConfig >/dev/null
wait_until "an omitted lock keeps the default timing" 15 idle_field_is '.lock' 300
idle_field_is '.lockConfigured' true || fail "an omitted lock stays configured" "$(idle_status)"
pass "an omitted lock stays configured"

# Everything below needs the compositor to actually report idle. Some
# environments (headless VMs among them) never do, and a timing assertion there
# would fail for reasons that have nothing to do with the timings.
set_idle 2 false

session_goes_idle() {
  local deadline=$((SECONDS + 45))

  while ((SECONDS < deadline)); do
    [[ $(idle_field '.idle') == "true" ]] && return 0
    sleep 2
  done

  return 1
}

if ! session_goes_idle; then
  pass "session never reports idle here; skipping idle-cycle assertions"
  exit 0
fi

# The regression itself: with the lock disabled, going idle must start the
# screensaver and leave the session unlocked.
wait_until "the screensaver still launches with the lock disabled" 60 \
  window_present 'org\.omarchy\.screensaver'
screenshot "success-screensaver-with-lock-disabled"

[[ $(idle_field '.timers.lock') == "false" ]] ||
  fail "a disabled lock never arms its timer" "$(idle_status)"
pass "a disabled lock never arms its timer"

lock_deadline=$((SECONDS + 30))
while ((SECONDS < lock_deadline)); do
  [[ $(omarchy-shell lock isLocked) == "false" ]] ||
    fail "a disabled lock never locks the session" "$(idle_status)"
  sleep 2
done
pass "a disabled lock never locks the session"

hyprctl dispatch closewindow "class:^(org\.omarchy\.screensaver)$" >/dev/null
wait_until "dismissing the screensaver ends the idle cycle" 30 idle_field_is '.inIdleCycle' false

# A configured lock must still be scheduled, at its own offset from the
# screensaver. Asserted on the armed timer rather than by letting it fire, so
# the suite does not strand later tests behind a lock screen.
set_idle 2 20

wait_until "a configured lock arms its timer once idle" 60 idle_field_is '.timers.lock' true
[[ $(idle_field '.lockDelay') == "18" ]] ||
  fail "a configured lock keeps its offset from the screensaver" "$(idle_status)"
pass "a configured lock keeps its offset from the screensaver"

hyprctl dispatch closewindow "class:^(org\.omarchy\.screensaver)$" >/dev/null
wait_until "the pending lock is cancelled with the screensaver" 30 idle_field_is '.timers.lock' false

screenshot "success-idle-timings-disabled"
