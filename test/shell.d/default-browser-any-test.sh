#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
flatpak_share="$test_tmp/flatpak/exports/share"
system_share="$test_tmp/usr/share"
browser_file="$test_tmp/browser"
terminal_log="$test_tmp/terminal-log"
notification_log="$test_tmp/notification-log"
select_log="$test_tmp/select-log"
mkdir -p "$mock_bin" "$test_home/.local/share/applications" "$flatpak_share/applications" "$system_share/applications"

cat >"$mock_bin/xdg-settings" <<'SH'
#!/bin/bash
case $1 in
get) [[ -f $OMARCHY_TEST_BROWSER_FILE ]] && cat "$OMARCHY_TEST_BROWSER_FILE" ;;
set) printf '%s\n' "$3" >"$OMARCHY_TEST_BROWSER_FILE" ;;
esac
SH
cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_TERMINAL_LOG"
SH
cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_NOTIFICATION_LOG"
SH
cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 0
SH
# Records the rows it was offered and answers with the row whose subtext
# matches OMARCHY_TEST_SELECT, the way the real picker returns "label<TAB>subtext".
cat >"$mock_bin/omarchy-menu-select" <<'SH'
#!/bin/bash
cat >"$OMARCHY_TEST_SELECT_LOG"
grep -P "\t${OMARCHY_TEST_SELECT}\$" "$OMARCHY_TEST_SELECT_LOG" | head -1 | cut -f2-
SH
chmod +x "$mock_bin"/*

cat >"$flatpak_share/applications/net.waterfox.waterfox.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Waterfox
Exec=/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=waterfox --file-forwarding net.waterfox.waterfox @@u %u @@
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
DESKTOP
cat >"$system_share/applications/chromium.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Chromium
Exec=/usr/bin/chromium %U
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
DESKTOP
cat >"$system_share/applications/hidden-browser.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Hidden
NoDisplay=true
Exec=/usr/bin/hidden %U
MimeType=x-scheme-handler/https;
DESKTOP
cat >"$system_share/applications/org.gnome.Calculator.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Calculator
Exec=gnome-calculator
MimeType=x-scheme-handler/calculator;
DESKTOP
# The user's own copy of an entry shadows the system one, so it is listed once.
cat >"$test_home/.local/share/applications/chromium.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Chromium (mine)
Exec=/usr/bin/chromium --flag %U
MimeType=x-scheme-handler/https;
DESKTOP

export HOME="$test_home"
export XDG_DATA_HOME="$test_home/.local/share"
export PATH="$mock_bin:$ROOT/bin:$PATH"
export XDG_DATA_DIRS="$flatpak_share:$system_share"
export OMARCHY_TEST_BROWSER_FILE="$browser_file"
export OMARCHY_TEST_TERMINAL_LOG="$terminal_log"
export OMARCHY_TEST_NOTIFICATION_LOG="$notification_log"
export OMARCHY_TEST_SELECT_LOG="$select_log"

[[ $(omarchy-cmd-desktop-entry path net.waterfox.waterfox.desktop) == "$flatpak_share/applications/net.waterfox.waterfox.desktop" ]] ||
  fail "desktop entry helper resolves an entry from a Flatpak export dir on XDG_DATA_DIRS"
[[ $(omarchy-cmd-desktop-entry path chromium.desktop) == "$test_home/.local/share/applications/chromium.desktop" ]] ||
  fail "desktop entry helper prefers the user's data dir"
[[ $(omarchy-cmd-desktop-entry name net.waterfox.waterfox.desktop) == "Waterfox" ]] ||
  fail "desktop entry helper reads the entry's name"
expected_exec=$'/usr/bin/flatpak\nrun\n--branch=stable\n--arch=x86_64\n--command=waterfox\n--file-forwarding\nnet.waterfox.waterfox'
[[ $(omarchy-cmd-desktop-entry exec net.waterfox.waterfox.desktop) == "$expected_exec" ]] ||
  fail "desktop entry helper keeps the whole flatpak command and drops the field codes" "$(omarchy-cmd-desktop-entry exec net.waterfox.waterfox.desktop)"
[[ $(omarchy-cmd-desktop-entry exec chromium.desktop) == $'/usr/bin/chromium\n--flag' ]] ||
  fail "desktop entry helper keeps fixed arguments and drops %U"
if omarchy-cmd-desktop-entry path missing.desktop >/dev/null; then
  fail "desktop entry helper fails on an unknown entry"
fi
pass "desktop entry helper resolves entries across XDG data dirs"

: >"$notification_log"
rm -f "$terminal_log"
omarchy-default-browser net.waterfox.waterfox.desktop
[[ $(<"$browser_file") == "net.waterfox.waterfox.desktop" ]] || fail "a desktop id becomes the default browser"
[[ $(omarchy-default-browser) == "net.waterfox.waterfox.desktop" ]] || fail "the default browser reports an unlisted browser by desktop id"
[[ ! -e $terminal_log ]] || fail "a desktop id never opens an installer"
grep -q 'Waterfox is now the default browser' "$notification_log" || fail "the notification names the browser from its desktop entry" "$(cat "$notification_log")"
pass "any installed browser can be made the default by desktop id"

printf 'chromium.desktop\n' >"$browser_file"
if omarchy-default-browser missing.desktop 2>/dev/null; then
  fail "an unknown desktop id is refused"
fi
[[ $(<"$browser_file") == "chromium.desktop" ]] || fail "an unknown desktop id leaves the default alone"
pass "a desktop id that resolves to nothing is refused"

OMARCHY_TEST_SELECT=net.waterfox.waterfox.desktop omarchy-menu-default-browser
[[ $(<"$browser_file") == "net.waterfox.waterfox.desktop" ]] || fail "the picker hands the chosen desktop id to omarchy-default-browser"
grep -q $'\tWaterfox\tnet.waterfox.waterfox.desktop$' "$select_log" || fail "the picker lists a Flatpak browser" "$(cat "$select_log")"
grep -q $'\tChromium (mine) ✓\tchromium.desktop$' "$select_log" || fail "the picker marks the current default and prefers the user's entry" "$(cat "$select_log")"
[[ $(grep -c 'chromium.desktop' "$select_log") == 1 ]] || fail "the picker lists a shadowed entry once" "$(cat "$select_log")"
if grep -q 'hidden-browser\|Calculator' "$select_log"; then
  fail "the picker skips hidden entries and non-browsers" "$(cat "$select_log")"
fi
pass "the browser picker offers every installed browser that handles web links"
