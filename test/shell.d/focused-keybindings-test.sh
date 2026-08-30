#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq

tmpdir=$(mktemp -d) && [[ -n $tmpdir && -d $tmpdir ]] ||
  fail "the test gets a temporary directory to stub the desktop in"
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
stub_bin="$tmpdir/bin"
data="$tmpdir/data"
mkdir -p "$home/.config/omarchy/keybindings" "$stub_bin" "$data/omarchy/keybindings" "$tmpdir/run"

# --- stubs -------------------------------------------------------------------
#
# The dispatcher asks Hyprland for the focused window and walks its process
# tree with ps and pgrep. Both are stood in for here: the window is whatever
# window.json says, and the tree is a flat "pid parent comm" table.

cat >"$stub_bin/hyprctl" <<'STUB'
#!/bin/bash
case "$1" in
  activewindow) cat "$STUB_WINDOW" ;;
  monitors) echo '[{"focused":true,"height":1000}]' ;;
  dispatch) echo "$*" >>"$STUB_LOG"; echo ok ;;
esac
STUB

cat >"$stub_bin/ps" <<'STUB'
#!/bin/bash
# ps -o comm= -p <pid>
awk -v pid="$4" '$1 == pid { print $3 }' "$STUB_TREE"
STUB

cat >"$stub_bin/pgrep" <<'STUB'
#!/bin/bash
# pgrep -P <pid>, or pgrep -x quickshell for the shell identity
if [[ $1 == "-P" ]]; then awk -v parent="$2" '$2 == parent { print $1 }' "$STUB_TREE"; exit 0; fi
if [[ $1 == "-x" && $2 == "quickshell" ]]; then echo 4242; exit 0; fi
exit 1
STUB

# The menu itself: records what it was offered and answers with a canned pick.
cat >"$stub_bin/omarchy-menu-select" <<'STUB'
#!/bin/bash
cat >"$STUB_OPTIONS"
[[ -n ${STUB_PICK:-} ]] && echo "$STUB_PICK"
STUB

cat >"$stub_bin/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf 'notify: %s | %s\n' "$1" "${2:-}" >>"$STUB_LOG"
STUB

cat >"$stub_bin/omarchy-menu" <<'STUB'
#!/bin/bash
echo "omarchy-menu $*" >>"$STUB_LOG"
STUB

# A stand-in for the stock global menu, so a fall-through is observable.
cat >"$stub_bin/omarchy-menu-keybindings" <<'STUB'
#!/bin/bash
echo "global-menu" >>"$STUB_LOG"
STUB

chmod +x "$stub_bin"/*

window() {
  jq -n --arg class "$1" --argjson pid "$2" '{class: $class, pid: $pid, address: "0xfeed"}' >"$tmpdir/window.json"
}

tree() {
  printf '%s\n' "$@" >"$tmpdir/tree.txt"
}

dispatch() {
  : >"$tmpdir/log"
  : >"$tmpdir/options"
  env -i PATH="$stub_bin:$ROOT/bin:$PATH" HOME="$home" OMARCHY_PATH="$ROOT" \
    XDG_DATA_DIRS="$data" XDG_RUNTIME_DIR="$tmpdir/run" \
    STUB_WINDOW="$tmpdir/window.json" STUB_TREE="$tmpdir/tree.txt" \
    STUB_LOG="$tmpdir/log" STUB_OPTIONS="$tmpdir/options" STUB_PICK="${1:-}" \
    bash "$ROOT/bin/omarchy-menu-focused-keybindings" "${@:2}" 2>&1
}

# --- which app is in front ---------------------------------------------------

window chromium 100
tree "100 1 chromium"
[[ $(dispatch "" --which) == *"app:    chromium"* ]] ||
  fail "a plain window resolves by class" "$(dispatch "" --which)"
pass "a plain window resolves by class"

window "chrome-hey.com__-Default" 100
[[ $(dispatch "" --which) == *"app:    chromium"* ]] ||
  fail "a Chromium web app resolves to chromium" "$(dispatch "" --which)"
pass "a Chromium web app resolves to chromium"

# The process tree is consulted first, so give this window a process nothing
# supports: what is being checked is that the class alone gets there.
printf '%s\n' 'CTRL + Q → Quit' >"$data/omarchy/keybindings/nautilus.txt"
window "org.gnome.Nautilus" 100
tree "100 1 .nautilus-wrapped"
[[ $(dispatch "" --which) == *"app:    nautilus"* ]] ||
  fail "a reverse-DNS class answers to its last component" "$(dispatch "" --which)"
pass "a reverse-DNS class answers to its last component"

# A terminal window is only interesting for what runs inside it.
printf '%s\n' 'CTRL + X → Stop' >"$data/omarchy/keybindings/claude.txt"
window foot 200
tree "200 1 foot" "201 200 bash" "202 201 claude" "203 202 claude"
which=$(dispatch "" --which)
[[ $which == *"app:    claude"* && $which == *"pid:    202"* ]] ||
  fail "a terminal resolves to the app inside it, at the process that owns it" "$which"
pass "a terminal resolves to the app inside it, at the process that owns it"

# tmux renames itself "tmux: client", and its panes live under the server,
# outside the window's tree. The pane-pid helper bridges that.
cat >"$stub_bin/omarchy-cmd-tmux-pane-pid" <<'STUB'
#!/bin/bash
echo 300
STUB
chmod +x "$stub_bin/omarchy-cmd-tmux-pane-pid"
printf '%s\n' 'PREFIX + c → Create window' >"$data/omarchy/keybindings/tmux.txt"
window foot 200
tree "200 1 foot" "201 200 tmux: client" "300 1 bash" "301 300 claude"
which=$(dispatch "" --which)
[[ $which == *"app:    claude"* && $which == *"pid:    301"* ]] ||
  fail "an app inside a multiplexer is found through the pane-pid helper" "$which"
pass "an app inside a multiplexer is found through the pane-pid helper"

# --- where lists come from ---------------------------------------------------

window chromium 100
tree "100 1 chromium"
printf '%s\n' 'CTRL + T → Shipped row' >"$data/omarchy/keybindings/chromium.txt"
dispatch >/dev/null
grep -q 'Shipped row' "$tmpdir/options" ||
  fail "a shipped list is read from the data dirs without being copied anywhere" "$(cat "$tmpdir/options")"
[[ ! -e "$home/.local/share/applications/chromium.txt" && -z $(ls "$home/.config/omarchy/keybindings") ]] ||
  fail "nothing is written into the user's home"
pass "a shipped list is read from the data dirs without being copied anywhere"

printf '%s\n' 'CTRL + T → User row' >"$home/.config/omarchy/keybindings/chromium.txt"
dispatch >/dev/null
grep -q 'User row' "$tmpdir/options" && ! grep -q 'Shipped row' "$tmpdir/options" ||
  fail "a list in the user's config wins over the shipped one" "$(cat "$tmpdir/options")"
pass "a list in the user's config wins over the shipped one"
rm "$home/.config/omarchy/keybindings/chromium.txt"

[[ $(head -1 "$tmpdir/options") == *"All Omarchy keybindings"* ]] ||
  fail "the global list is the first, preselected row of an app menu" "$(head -1 "$tmpdir/options")"
pass "the global list is the first, preselected row of an app menu"

window "some.unknown.App" 100
tree "100 1 unknown-app"
dispatch >/dev/null
grep -q 'global-menu' "$tmpdir/log" ||
  fail "an app with no list falls through to Omarchy's own menu" "$(cat "$tmpdir/log")"
pass "an app with no list falls through to Omarchy's own menu"

# --- what a picked row sends -------------------------------------------------

sent() { grep -o 'key = "[^"]*", state = "down"' "$tmpdir/log" | sed 's/key = "//; s/", state.*//' | paste -sd' '; }
mods() { grep -o 'mods = "[^"]*", key = "[^"]*", state = "down"' "$tmpdir/log" | sed 's/mods = "//; s/", key.*//' | paste -sd'|'; }

window chromium 100
tree "100 1 chromium"
cat >"$data/omarchy/keybindings/chromium.txt" <<'ROWS'
CTRL + T                         → New tab
CTRL + X CTRL + K                → A two-chord sequence
CTRL + ?                         → Shifted punctuation
G                                → A bare capital
ENTER / CTRL + O                 → Alternates
CTRL + 1..8                      → A range
ROWS

dispatch 'CTRL + T                         → New tab' >/dev/null
[[ $(sent) == "t" && $(mods) == "CTRL" ]] ||
  fail "a chord is replayed into the window" "$(cat "$tmpdir/log")"
grep -q 'window = "address:0xfeed"' "$tmpdir/log" ||
  fail "keys go to the window the list was built for" "$(cat "$tmpdir/log")"
pass "a chord is replayed into the window it was listed for"

dispatch 'CTRL + X CTRL + K                → A two-chord sequence' >/dev/null
[[ $(sent) == "x k" ]] ||
  fail "a sequence is sent chord by chord, in order" "$(cat "$tmpdir/log")"
pass "a sequence is sent chord by chord, in order"

dispatch 'CTRL + ?                         → Shifted punctuation' >/dev/null
[[ $(sent) == "slash" && $(mods) == "CTRL SHIFT" ]] ||
  fail "shifted punctuation is sent as SHIFT plus its base key" "$(cat "$tmpdir/log")"
pass "shifted punctuation is sent as SHIFT plus its base key"

dispatch 'G                                → A bare capital' >/dev/null
[[ $(sent) == "g" && $(mods) == "SHIFT" ]] ||
  fail "a bare capital letter is a shifted key" "$(cat "$tmpdir/log")"
pass "a bare capital letter is a shifted key"

dispatch 'ENTER / CTRL + O                 → Alternates' >/dev/null
[[ $(sent) == "return" ]] ||
  fail "a row with alternates sends the first" "$(cat "$tmpdir/log")"
pass "a row with alternates sends the first"

dispatch 'CTRL + 1..8                      → A range' >/dev/null
[[ -z $(sent) ]] && grep -q 'notify: Not a single keypress' "$tmpdir/log" ||
  fail "a range is shown but refused with an explanation, not sent" "$(cat "$tmpdir/log")"
pass "a range is shown but refused with an explanation, not sent"

# --- pressing the binding again ---------------------------------------------
#
# Stock Super+K leaves every superseded omarchy-menu-select waiting forever
# (#9057). Here the second press finds the first still up and ends it.

cat >"$stub_bin/omarchy-menu-select" <<'STUB'
#!/bin/bash
cat >"$STUB_OPTIONS"
sleep 30
STUB
chmod +x "$stub_bin/omarchy-menu-select"
window chromium 100
tree "100 1 chromium"
dispatch >/dev/null 2>&1 &
first=$!
sleep 1
dispatch >/dev/null 2>&1
sleep 1
if kill -0 "$first" 2>/dev/null; then
  kill "$first" 2>/dev/null
  fail "a second press closes the menu the first press opened instead of stacking another"
fi
grep -q 'omarchy-menu close' "$tmpdir/log" ||
  fail "the second press tells the shell to close the menu" "$(cat "$tmpdir/log")"
pass "a second press closes the menu the first press opened instead of stacking another"
