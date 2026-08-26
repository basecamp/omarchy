#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
stub="$tmpdir/bin"
mkdir -p "$home" "$stub"

cat >"$stub/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$SHELL_LOG"
if [[ $1 == "-q" ]]; then
  shift
fi
if [[ $1 == "notifications" && $2 == "dndState" ]]; then
  printf '%s\n' "${DND_STATE:-off}"
  exit 0
fi
if [[ $1 == "notifications" && $2 == "setDnd" ]]; then
  printf '%s\n' "$3" >"$DND_SET_LOG"
  exit 0
fi
exit 0
SH
cat >"$stub/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
SH
chmod +x "$stub/omarchy-shell" "$stub/omarchy-notification-send"

run() {
  HOME="$home" PATH="$stub:$ROOT/bin:$PATH" \
    SHELL_LOG="$tmpdir/shell.log" DND_SET_LOG="$tmpdir/dnd" NOTIFY_LOG="$tmpdir/notify" \
    DND_STATE="${DND_STATE:-off}" \
    "$ROOT/bin/omarchy-toggle-presentation" "$@"
}

status=$(run on)
[[ $status == "on" ]] || fail "presentation on prints on" "$status"
[[ -f $home/.local/state/omarchy/toggles/presentation ]] ||
  fail "presentation on sets the presentation flag"
[[ -f $home/.local/state/omarchy/toggles/bar-off ]] ||
  fail "presentation on hides the bar"
[[ -f $home/.local/state/omarchy/indicators/stay-awake ]] ||
  fail "presentation on stays awake"
[[ $(<"$tmpdir/dnd") == "on" ]] ||
  fail "presentation on silences notifications" "$(cat "$tmpdir/dnd")"
grep -Fq 'Presentation mode on' "$tmpdir/notify" ||
  fail "presentation on notifies" "$(cat "$tmpdir/notify")"
pass "presentation on hides the bar, silences notifications, and stays awake"

: >"$tmpdir/dnd"
: >"$tmpdir/notify"
status=$(run off)
[[ $status == "off" ]] || fail "presentation off prints off" "$status"
[[ ! -f $home/.local/state/omarchy/toggles/presentation ]] ||
  fail "presentation off clears the presentation flag"
[[ ! -f $home/.local/state/omarchy/toggles/bar-off ]] ||
  fail "presentation off shows the bar again when it was visible"
[[ ! -f $home/.local/state/omarchy/indicators/stay-awake ]] ||
  fail "presentation off allows idle when stay-awake was off"
[[ $(<"$tmpdir/dnd") == "off" ]] ||
  fail "presentation off restores notifications" "$(cat "$tmpdir/dnd")"
pass "presentation off restores the previous bar, dnd, and idle state"

# Already presenting: bar hidden, dnd on, stay-awake on — turning presentation
# off must leave those alone.
mkdir -p "$home/.local/state/omarchy/toggles" "$home/.local/state/omarchy/indicators"
touch "$home/.local/state/omarchy/toggles/bar-off"
touch "$home/.local/state/omarchy/indicators/stay-awake"
DND_STATE=on
: >"$tmpdir/dnd"
run on >/dev/null
: >"$tmpdir/dnd"
run off >/dev/null
[[ -f $home/.local/state/omarchy/toggles/bar-off ]] ||
  fail "presentation off leaves a bar that was already hidden"
[[ -f $home/.local/state/omarchy/indicators/stay-awake ]] ||
  fail "presentation off leaves stay-awake that was already on"
[[ ! -s $tmpdir/dnd ]] ||
  fail "presentation off does not clear dnd that was already on" "$(cat "$tmpdir/dnd")"
pass "presentation off does not undo state it did not change"

grep -Fq '"trigger.toggle.presentation"' "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "presentation mode is on the Toggle menu"
pass "presentation mode is on the Toggle menu"
