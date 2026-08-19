#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export PATH="$ROOT/bin:$PATH"

theme_dir="$TMPDIR/.local/state/omarchy/current/theme"
profile="$TMPDIR/.config/zen/abcd1234.Default"
mkdir -p "$theme_dir" "$profile"
touch "$profile/prefs.js"

echo 'user_pref("zen.theme.accent-color", "#7aa2f7");' >"$theme_dir/zen.js"

HOME="$TMPDIR" omarchy-theme-set-zen

expected='user_pref("zen.theme.accent-color", "#7aa2f7");'
[[ $(<"$profile/user.js") == "$expected" ]] ||
  fail "the generated theme file lands in a Zen profile" "expected $expected, got $(<"$profile/user.js")"
pass "the generated theme file lands in a Zen profile"

cat >"$profile/user.js" <<'PREFS'
user_pref("zen.welcome-screen.seen", true);
user_pref("zen.theme.accent-color", "#00ff00");
user_pref("browser.tabs.closeWindowWithLastTab", true);
PREFS

HOME="$TMPDIR" omarchy-theme-set-zen

grep -q '^user_pref("zen.welcome-screen.seen", true);$' "$profile/user.js" &&
  grep -q '^user_pref("browser.tabs.closeWindowWithLastTab", true);$' "$profile/user.js" ||
  fail "preferences the user owns survive a theme change" "user.js lost user-owned entries"
pass "preferences the user owns survive a theme change"

(( $(grep -c "zen.theme.accent-color" "$profile/user.js") == 1 )) &&
  grep -q "$expected" "$profile/user.js" ||
  fail "a stale accent is replaced rather than appended" "got $(grep -c "zen.theme.accent-color" "$profile/user.js") accent lines"
pass "a stale accent is replaced rather than appended"

# The script drops whatever the theme file declares, so a second pref needs no
# code change -- only a longer template.
cat >"$theme_dir/zen.js" <<'GENERATED'
user_pref("zen.theme.accent-color", "#bb9af7");
user_pref("zen.theme.border-radius", 4);
GENERATED

HOME="$TMPDIR" omarchy-theme-set-zen
HOME="$TMPDIR" omarchy-theme-set-zen

(( $(grep -c "zen.theme.accent-color" "$profile/user.js") == 1 )) &&
  (( $(grep -c "zen.theme.border-radius" "$profile/user.js") == 1 )) &&
  grep -q '^user_pref("zen.welcome-screen.seen", true);$' "$profile/user.js" ||
  fail "every pref the theme declares is managed, and repeated runs stay idempotent" "$(cat "$profile/user.js")"
pass "every pref the theme declares is managed, and repeated runs stay idempotent"

not_a_profile="$TMPDIR/.config/zen/Profile Groups"
mkdir -p "$not_a_profile"

HOME="$TMPDIR" omarchy-theme-set-zen

[[ ! -f $not_a_profile/user.js ]] ||
  fail "directories without prefs.js are skipped" "wrote user.js into $not_a_profile"
pass "directories without prefs.js are skipped"

rm "$theme_dir/zen.js"
cp "$profile/user.js" "$TMPDIR/user.js.before"

HOME="$TMPDIR" omarchy-theme-set-zen

diff -q "$TMPDIR/user.js.before" "$profile/user.js" >/dev/null ||
  fail "a theme without a zen.js leaves profiles untouched" "user.js changed with no generated theme file"
pass "a theme without a zen.js leaves profiles untouched"

no_zen=$(mktemp -d)
mkdir -p "$no_zen/.local/state/omarchy/current/theme"
echo 'user_pref("zen.theme.accent-color", "#7aa2f7");' >"$no_zen/.local/state/omarchy/current/theme/zen.js"

HOME="$no_zen" omarchy-theme-set-zen ||
  fail "a machine without Zen is a no-op" "command failed when ~/.config/zen is missing"
pass "a machine without Zen is a no-op"

rm -rf "$no_zen"

# End to end: the template is what actually produces zen.js at theme-set time.
render=$(mktemp -d)
mkdir -p "$render/.local/state/omarchy/current/next-theme"
cp "$ROOT/themes/tokyo-night/colors.toml" "$render/.local/state/omarchy/current/next-theme/"

HOME="$render" OMARCHY_PATH="$ROOT" omarchy-theme-set-templates

rendered="$render/.local/state/omarchy/current/next-theme/zen.js"
[[ -f $rendered ]] ||
  fail "the template renders zen.js for a theme that does not ship one" "no zen.js generated"
[[ $(<"$rendered") == 'user_pref("zen.theme.accent-color", "#7aa2f7");' ]] ||
  fail "the template renders zen.js for a theme that does not ship one" "got $(<"$rendered")"
pass "the template renders zen.js for a theme that does not ship one"

rm -rf "$render"
