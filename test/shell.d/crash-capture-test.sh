#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"
SYSTEMCTL_LOG="$TMPDIR/systemctl-log"

cat >"$TMPDIR/bin/systemctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
SH

cat >"$TMPDIR/bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$TMPDIR/bin/systemctl" "$TMPDIR/bin/omarchy-notification-send"

test_home="$TMPDIR/home"
flag="$test_home/.local/state/omarchy/toggles/crash-capture-off"

toggle_crash_capture() {
  PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
  SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
  HOME="$test_home" \
    "$ROOT/bin/omarchy-toggle-crash-capture"
}

toggle_crash_capture
[[ -f $flag ]] || fail "crash capture toggle disables the watcher"
grep -Fqx -- "--user stop omarchy-crash-watch.service" "$SYSTEMCTL_LOG" ||
  fail "crash capture toggle stops the running watcher, so disabling takes effect before the next login"
pass "crash capture toggle disables the watcher"

: >"$SYSTEMCTL_LOG"
toggle_crash_capture
[[ ! -f $flag ]] || fail "crash capture toggle re-enables the watcher"
grep -Fqx -- "--user start omarchy-crash-watch.service" "$SYSTEMCTL_LOG" ||
  fail "crash capture toggle starts the watcher, so enabling takes effect before the next login"
pass "crash capture toggle re-enables the watcher"

service="$ROOT/default/systemd/user/omarchy-crash-watch.service"
grep -Fx 'ConditionPathExists=!%h/.local/state/omarchy/toggles/crash-capture-off' "$service" >/dev/null ||
  fail "the watcher is pulled back in at every login, so disabling it never survives a logout"
pass "crash watcher stays disabled across logins"

grep -F 'omarchy-crash-watch.service' "$ROOT/install/user/first-run/enable-user-units.sh" >/dev/null ||
  fail "crash capture is no longer on by default for new installs"
pass "crash capture is on by default"

require_command jq

# The per-program mute, driven through the real watcher with a stubbed journal:
# these prove what a person sees -- a toast arriving or not -- where asserting
# that a flag file was read would prove only that a flag file was read.
watch_bin="$TMPDIR/watch-bin"
watch_home="$TMPDIR/watch-home"
NOTIFY_LOG="$TMPDIR/notify-log"
JOURNAL_ENTRIES="$TMPDIR/journal-entries"

mkdir -p "$watch_bin" "$watch_home"

cat >"$watch_bin/journalctl" <<'SH'
#!/bin/bash
cat "$JOURNAL_ENTRIES"
SH

cat >"$watch_bin/omarchy-default-agent" <<'SH'
#!/bin/bash
echo claude
SH

cat >"$watch_bin/omarchy-notification-wait" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$watch_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
SH

chmod +x "$watch_bin/journalctl" "$watch_bin/omarchy-default-agent" \
  "$watch_bin/omarchy-notification-wait" "$watch_bin/omarchy-notification-send"

reset_entries() {
  : >"$JOURNAL_ENTRIES"
}

# One core dump as systemd-coredump journals it. The UID must be this user's, or
# the watcher discards it as somebody else's crash before anything under test.
crash_entry() {
  local comm="$1" exe="$2"

  jq -cn --arg uid "$UID" --arg comm "$comm" --arg exe "$exe" \
    '{_UID: $uid, COREDUMP_COMM: $comm, COREDUMP_PID: "4242",
      COREDUMP_EXE: $exe, COREDUMP_SIGNAL_NAME: "SIGSEGV"}' >>"$JOURNAL_ENTRIES"
}

# The stubbed journalctl ends after the entries, so the watcher's loop ends too.
# Its exit status is asserted rather than discarded: a watcher that dies on a
# muted crash notifies about nothing afterwards, which every assertion below
# that expects silence would otherwise read as success.
run_watch() {
  local status=0

  : >"$NOTIFY_LOG"

  PATH="$watch_bin:$ROOT/bin:$PATH" \
  JOURNAL_ENTRIES="$JOURNAL_ENTRIES" \
  NOTIFY_LOG="$NOTIFY_LOG" \
  HOME="$watch_home" \
    "$ROOT/bin/omarchy-crash-watch" || status=$?

  (( status == 0 )) ||
    fail "the watcher exited $status rather than carrying on, so a mute takes the service down with it"
}

mute() {
  HOME="$watch_home" "$ROOT/bin/omarchy-toggle" "crash-ignore/$1" "$2"
}

announced() {
  grep -Fq "Process crashed: $1" "$NOTIFY_LOG"
}

reset_entries
crash_entry hyprland /usr/bin/hyprland
run_watch
announced hyprland ||
  fail "a crash nobody muted still announces itself"
pass "a crash nobody muted still announces itself"

mute hyprland on
run_watch
! announced hyprland ||
  fail "muting a program stops the crash notifications the diagnosis offered to stop"
pass "muting a program stops its crash notifications"

reset_entries
crash_entry nautilus /usr/bin/nautilus
run_watch
announced nautilus ||
  fail "muting one program silences every other program, which is the global toggle's job and not this one's"
pass "muting one program leaves every other program announcing"

mute hyprland off
reset_entries
crash_entry hyprland /usr/bin/hyprland
run_watch
announced hyprland ||
  fail "un-muting a program brings its crash notifications back"
pass "un-muting a program brings its crash notifications back"

# The diagnosis tells the user to mute the name the toast showed them, so the
# toast has to show the name the watcher checks. COMM is truncated to 15
# characters and the executable's basename is not, and announcing the truncated
# one would leave a dutifully-followed mute matching nothing forever.
reset_entries
crash_entry chromium-browse /usr/lib/chromium/chromium-browser
run_watch
announced chromium-browser ||
  fail "the toast announces a name the mute cannot be keyed on, so following the diagnosis mutes nothing"
pass "the toast announces the name the mute is keyed on"

mute chromium-browser on
run_watch
! announced chromium-browser ||
  fail "the mute is keyed on the name the notification announced, not on the truncated COMM"
pass "muting the announced name silences a program whose COMM was truncated"

# A muted crash must not end the watcher. Restart=always would paper over it
# with a five-second gap, and the watcher restarts on `journalctl -n 0`, which
# never replays the crashes it missed while it was away.
reset_entries
crash_entry chromium-browse /usr/lib/chromium/chromium-browser
crash_entry nautilus /usr/bin/nautilus
run_watch
announced nautilus ||
  fail "a muted crash stops the watcher reading the journal, losing every crash after it"
pass "a muted crash does not stop the watcher reading the next one"

# A process can set its own comm to anything prctl takes, slashes included, and
# a crash with no recorded executable falls back to it. A name that climbed out
# of crash-ignore/ would let a crashing program silence itself against an
# unrelated flag -- and have the diagnosis write one there on the user's behalf.
# The fixture carries two slashes so that dropping only the first is not mistaken
# for dropping all of them.
reset_entries
crash_entry a/../bar-off -
sibling_flag="$watch_home/.local/state/omarchy/toggles/bar-off"
touch "$sibling_flag"
run_watch
announced bar-off ||
  fail "a comm that climbs out of crash-ignore/ reads an unrelated toggle, letting a crash suppress its own notification"
pass "a comm that climbs out of crash-ignore/ cannot reach an unrelated toggle"
rm -f "$sibling_flag"

# Stripping to the last component does not always leave a component. An empty
# name is no kind of array subscript and no kind of toast, and a dot component
# names a directory the mute would touch and then never match.
for empty_comm in / a/ . ..; do
  reset_entries
  crash_entry "$empty_comm" -
  run_watch
  announced unknown ||
    fail "a comm of '$empty_comm' leaves no usable name, so the toast cannot say what crashed and the mute has nothing to key on"
done
pass "a comm that strips down to nothing or a dot still announces under a name a mute can use"

# Only "." and ".." are special. A leading dot is an ordinary filename, and
# folding those into the fallback would have one program's mute silence another.
for dotted_comm in .hidden ...; do
  reset_entries
  crash_entry "$dotted_comm" -
  run_watch
  announced "$dotted_comm" ||
    fail "'$dotted_comm' is an ordinary name, but it lands in the fallback, so muting it would silence unrelated crashes"
done
pass "a leading dot is an ordinary name rather than a special component"

# And the name it settles on is mutable like any other.
mute unknown on
reset_entries
crash_entry / -
run_watch
! announced unknown ||
  fail "the fallback name cannot be muted, so the one crash most likely to repeat is the one that cannot be silenced"
pass "the fallback name can be muted like any other"
mute unknown off

skill="$ROOT/default/agents/skills/diagnose-crash/SKILL.md"
grep -Fq 'crash-ignore/' "$skill" ||
  fail "the diagnosis no longer offers the mute under the name the watcher reads, so the two have drifted apart"
grep -Fq 'crash-ignore/$name' "$ROOT/bin/omarchy-crash-watch" ||
  fail "the watcher no longer reads the flag the diagnosis offers to write"
pass "the diagnosis and the watcher name the same flag"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const items = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const byId = Object.fromEntries(items.map(item => [item.id, item]))

assertEqual(
  byId['trigger.toggle.crash-capture'].action,
  'omarchy-toggle-crash-capture',
  'menu toggles crash capture from Trigger > Toggle'
)
JS
