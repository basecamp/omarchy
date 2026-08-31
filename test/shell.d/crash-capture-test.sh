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

# Through the real command rather than writing the flag by hand: these assertions
# are then the guard that the thing the diagnosis runs and the thing the watcher
# reads have not drifted apart.
mute() {
  HOME="$watch_home" PATH="$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-crash-mute" "$1" "$2" >/dev/null
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

# An empty comm is not a missing entry. Tab is IFS whitespace, so an empty field
# collapses and every field after it shifts along one -- the pid becomes a path,
# the crash reads as somebody else's, and it is dropped without a word.
reset_entries
crash_entry "" -
crash_entry nautilus /usr/bin/nautilus
run_watch
announced unknown ||
  fail "a crash whose comm is empty is dropped instead of announced, because the empty field shifted every field after it"
announced nautilus ||
  fail "an empty comm derails the rest of the journal entry"
pass "an empty comm is announced rather than parsed into the next field"

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

# What omarchy-crash-mute does on its own. That it agrees with the watcher is
# already covered above, which drives it for every mute it makes.
mute_home="$TMPDIR/mute-home"
mkdir -p "$mute_home"

crash_mute() {
  HOME="$mute_home" PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-crash-mute" "$@"
}

mute_flag() {
  [[ $1 == "--" ]] && shift
  printf '%s' "$mute_home/.local/state/omarchy/toggles/crash-ignore/$1"
}

crash_mute | grep -Fq "No programs muted" ||
  fail "an empty mute list prints nothing, so a user cannot tell it from a broken command"
pass "the command says so when nothing is muted"

crash_mute hyprland >/dev/null
crash_mute | grep -Fqx hyprland ||
  fail "a muted program is missing from the list, so a mute cannot be found again to lift it"
pass "the command lists what it muted"

# The watcher keys on the basename, so the command has to take the path a crash
# recorded and land on the same flag the watcher will look for.
crash_mute /usr/lib/chromium/chromium-browser >/dev/null
[[ -f $(mute_flag chromium-browser) ]] ||
  fail "a binary's path is muted verbatim rather than by name, so the watcher never sees that flag"
pass "the command reduces a path to the name the watcher checks"

crash_mute hyprland off >/dev/null
[[ ! -f $(mute_flag hyprland) ]] ||
  fail "off leaves the program muted, making the mute a one-way door"
pass "the command un-mutes"

# Muting is not flipping. The diagnosis offers this on a program the user may
# already have muted, and asking for a mute twice has to leave it muted.
crash_mute hyprland >/dev/null
crash_mute hyprland >/dev/null
[[ -f $(mute_flag hyprland) ]] ||
  fail "muting an already-muted program un-mutes it, so offering the mute a second time turns it back on"
pass "asking to mute twice leaves it muted"

# A program may legitimately be called .hidden, and a mute nobody can see is a
# mute nobody can lift.
crash_mute .hidden >/dev/null
crash_mute | grep -Fqx .hidden ||
  fail "a mute on a dotted name is missing from the list, so it can never be found and lifted"
pass "the list shows a name that begins with a dot"

# It turns what it is given into a path, so it has to refuse whatever is not one
# component of one.
for bad_name in . .. /; do
  ! crash_mute "$bad_name" >/dev/null 2>&1 ||
    fail "'$bad_name' is taken as a program name, and the flag that writes is not one the watcher will ever read"
done
pass "the command refuses a name that is not a name"

! crash_mute hyprland sideways >/dev/null 2>&1 ||
  fail "an action it does not know is treated as a mute, so a typo silences a program"
pass "the command refuses an action it does not know"

# And says what it refused, or the user retypes the same thing. Captured rather
# than piped: the command exits non-zero here, which pipefail would surface as
# the pipeline's status and read as a failed assertion.
refusal=$(crash_mute hyprland sideways 2>&1) || true
grep -Fq "Not an action" <<<"$refusal" ||
  fail "an unknown action is refused without naming it, leaving the user nothing to correct"
pass "the command names the action it refused"

crash_mute ../bar-off >/dev/null
[[ ! -e "$mute_home/.local/state/omarchy/toggles/bar-off" ]] ||
  fail "a name that climbs out writes a sibling toggle, so muting a crash could turn off the bar instead"
pass "the command cannot be talked into writing outside crash-ignore/"

# A program may be called -h, and the router answers that with its own help
# before the command runs. A leading -- is the way through, so it has to be
# consumed rather than taken for the program name.
crash_mute -- -h >/dev/null 2>&1 ||
  fail "a leading -- is refused rather than consumed, so a program named like a flag cannot be muted at all"
[[ -f $(mute_flag -- -h) ]] ||
  fail "a leading -- is taken for the program name, so muting -h mutes something else"
pass "a leading -- lets a program named like a flag be muted"

# toggle is advertised, so it has to flip both ways rather than quietly mute.
crash_mute toggler off >/dev/null
crash_mute toggler toggle >/dev/null
[[ -f $(mute_flag toggler) ]] ||
  fail "toggle does not mute an un-muted program"
crash_mute toggler toggle >/dev/null
[[ ! -f $(mute_flag toggler) ]] ||
  fail "toggle mutes but never un-mutes, so the advertised action only goes one way"
pass "toggle flips a mute both ways"

# The listing means what the watcher means, and the watcher honours a regular
# file. Anything else in there is not a mute, however much it looks like one.
mkdir -p "$(mute_flag notactuallymuted)"
! crash_mute | grep -Fqx notactuallymuted ||
  fail "a directory is reported as muted while that program's crashes keep arriving"
pass "the listing counts only the flags the watcher honours"
rmdir "$(mute_flag notactuallymuted)"

# A mute that could not be written must not be reported as one. Without this the
# command can print success for a flag that was never created.
failing_bin="$TMPDIR/failing-bin"
mkdir -p "$failing_bin"
cat >"$failing_bin/omarchy-toggle" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$failing_bin/omarchy-toggle"

status=0
refusal=$(HOME="$mute_home" PATH="$failing_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-crash-mute" hyprland 2>&1) || status=$?
(( status != 0 )) ||
  fail "a mute that could not be written exits zero, so nothing downstream learns it failed"
! grep -Fq "Muted crash notifications" <<<"$refusal" ||
  fail "a mute that could not be written still reports success, so the user believes a program is silenced when it is not"
pass "a mute that could not be written is not reported as one"

skill="$ROOT/default/agents/skills/diagnose-crash/SKILL.md"
grep -Fq 'omarchy-crash-mute' "$skill" ||
  fail "the diagnosis no longer names the command that mutes, so the offer it makes cannot be carried out"
pass "the diagnosis names the command that mutes"

grep -Fq 'GROUP_DESCRIPTIONS[crash]' "$ROOT/bin/omarchy" ||
  fail "the crash group has no description, so the router lists a group it cannot describe"
pass "the crash group is described in the router"

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
