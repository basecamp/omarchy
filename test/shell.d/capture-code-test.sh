#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
log_file="$test_tmp/capture.log"
out_dir="$test_tmp/pictures"
mkdir -p "$stub_bin" "$out_dir"

export OMARCHY_CAPTURE_TEST_LOG="$log_file"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<<"$body"
  chmod +x "$stub_bin/$name"
}

log_call() {
  cat <<'STUB'
log() {
  printf "%s" "$1" >>"$OMARCHY_CAPTURE_TEST_LOG"
  shift
  for arg in "$@"; do printf "\t%s" "$arg" >>"$OMARCHY_CAPTURE_TEST_LOG"; done
  printf "\n" >>"$OMARCHY_CAPTURE_TEST_LOG"
}
STUB
}

write_stub hyprctl "#!/bin/bash
printf '{\"title\": \"%s\"}' \"\${OMARCHY_TEST_TITLE:-}\"
"

write_stub wl-paste "#!/bin/bash
$(log_call)
log wl-paste \"\$@\"
printf '%s' \"\${OMARCHY_TEST_CLIPBOARD:-}\"
"

write_stub wl-copy "#!/bin/bash
$(log_call)
log wl-copy \"\$@\"
cat >/dev/null
"

# Writes a real file so the caller's -f checks behave like the real thing,
# unless OMARCHY_TEST_SILICON_FAIL is set: real silicon exits 0 and leaves no
# file behind on failures such as an unsupported language or a broken theme,
# after printing a diagnostic to stderr.
write_stub silicon "#!/bin/bash
$(log_call)
log silicon \"\$@\"
if [[ -n \${OMARCHY_TEST_SILICON_FAIL:-} ]]; then
  echo \"\$OMARCHY_TEST_SILICON_FAIL\" >&2
  exit 0
fi
while [[ \$# -gt 0 ]]; do
  if [[ \$1 == \"-o\" ]]; then printf 'PNG' >\"\$2\"; fi
  shift
done
"

write_stub gum "#!/bin/bash
$(log_call)
log gum \"\$@\"
printf '%s' \"\${OMARCHY_TEST_GUM_PICK:-}\"
exit \${OMARCHY_TEST_GUM_EXIT:-0}
"

write_stub omarchy-notification-send "#!/bin/bash
$(log_call)
log notify \"\$@\"
"

# Stands in for the real uwsm-app during the no-tty handoff: setsid is left
# real (it just execs the next argument), so this is the first stubbed
# command in that chain. Logs the xdg-terminal-exec invocation it was asked
# to run and lets a scenario control whether the handoff itself succeeds.
write_stub uwsm-app "#!/bin/bash
$(log_call)
log uwsm-app \"\$@\"
exit \${OMARCHY_TEST_UWSM_EXIT:-0}
"

write_stub identify "#!/bin/bash
$(log_call)
log identify \"\$@\"
printf '100'
"

# The real omarchy-font-current shells out to fc-match, so the developer's own
# font would otherwise decide what these assertions see. Stubbed so the family
# is a fixture, and so a scenario can make it come back empty.
write_stub omarchy-font-current "#!/bin/bash
printf '%s' \"\${OMARCHY_TEST_FONT-Test Mono}\"
"

# Writes a distinguishable marker to the destination (the last argument,
# stripping a possible png: prefix) so a test can tell the bordered image
# apart from silicon's plain one, unless OMARCHY_TEST_MAGICK_FAIL is set: a
# failed (or missing) magick must degrade to the unbordered image, not fail
# the capture.
write_stub magick "#!/bin/bash
$(log_call)
log magick \"\$@\"
if [[ -n \${OMARCHY_TEST_MAGICK_FAIL:-} ]]; then
  echo 'magick: test failure' >&2
  exit 1
fi
dest=\"\${@: -1}\"
dest=\"\${dest#png:}\"
printf 'BORDERED-PNG' >\"\$dest\"
"

# A throwaway HOME and XDG_CACHE_HOME keep the run hermetic: Task 5 reads the
# active theme under $HOME and caches under $XDG_CACHE_HOME, and the result must
# not depend on the developer's real theme state. $ROOT/bin is on PATH so the
# real omarchy-theme-color is used rather than an installed copy.
fake_home="$test_tmp/home"
theme_dir="$fake_home/.local/state/omarchy/current/theme"
mkdir -p "$theme_dir"

# CAPTURE_EXIT holds the wrapped command's real exit status. Scenarios that
# legitimately fail must read it explicitly instead of letting it propagate:
# under `set -e`, a bare call to either runner below would otherwise abort
# this whole test file the first time the wrapped command exits non-zero.
CAPTURE_EXIT=0

# The default runner: a plain bash invocation with stdin from /dev/null, no
# controlling terminal at all. This matches the real Hyprland keybinding and
# menu action (both invoke the command with no tty), and it is also what lets
# the success notification's backgrounded editor-click subshell survive long
# enough to write to the log: a pty session (see run_capture_tty below) sends
# SIGHUP to anything still attached to it once the wrapped command exits,
# killing an unrelated background job before it can run.
run_capture() {
  : >"$log_file"
  set +e
  PATH="$stub_bin:$ROOT/bin:$PATH" OMARCHY_SCREENSHOT_DIR="$out_dir" \
    HOME="$fake_home" XDG_CACHE_HOME="$test_tmp/cache" OMARCHY_PATH="$ROOT" \
    bash "$ROOT/bin/omarchy-capture-code" "$@" </dev/null >"$test_tmp/out" 2>&1
  CAPTURE_EXIT=$?
  set -e
  # Let a success notification's backgrounded editor-click subshell settle
  # before returning: otherwise it could still be writing to the log by the
  # time the *next* scenario truncates it, bleeding a stray "notify" line
  # into that scenario's assertions.
  sleep 0.2
}

# Only for scenarios that must exercise the interactive gum picker directly:
# gum's own `[[ -t 0 ]]` check needs a real controlling terminal, which
# `script` provides by allocating a pty.
run_capture_tty() {
  : >"$log_file"
  set +e
  PATH="$stub_bin:$ROOT/bin:$PATH" OMARCHY_SCREENSHOT_DIR="$out_dir" \
    HOME="$fake_home" XDG_CACHE_HOME="$test_tmp/cache" OMARCHY_PATH="$ROOT" \
    script -qec "bash '$ROOT/bin/omarchy-capture-code' $*" /dev/null >"$test_tmp/out" 2>&1
  CAPTURE_EXIT=$?
  set -e
}

# Patterns starting with a dash are escaped by the caller (\-\-theme), not passed
# as a bare `--` argument: the helpers already pass `--` to grep, so an extra one
# would shift the pattern into $2 and leave an assertion that always passes.
#
# Success notifications now fire from a backgrounded subshell (matching
# omarchy-capture-screenshot's clickable pattern), so the log line can land a
# moment after the wrapped command already returned. Poll briefly rather than
# failing on the first miss.
assert_logged() {
  local pattern="$1"
  local description="$2"
  local attempt

  [[ -n $description ]] || fail "assert_logged called without a description" "pattern: $pattern"

  for attempt in {1..20}; do
    grep -q -- "$pattern" "$log_file" && { pass "$description"; return; }
    sleep 0.05
  done

  fail "$description" "$(cat "$log_file")"
}

refute_logged() {
  local pattern="$1"
  local description="$2"

  [[ -n $description ]] || fail "refute_logged called without a description" "pattern: $pattern"
  if grep -q -- "$pattern" "$log_file"; then
    fail "$description" "$(cat "$log_file")"
  fi
  pass "$description"
}

# --- Language comes from the focused window title ------------------------------

OMARCHY_TEST_TITLE="config.rs — omarchy" \
  OMARCHY_TEST_CLIPBOARD="let x = 1;" run_capture

assert_logged $'silicon\t.*-l\trs' "passes the extension from the window title to silicon"
refute_logged '^gum' "does not prompt when the title identifies the language"
refute_logged '\-\-window-title' "never renders the filename into the image"
assert_logged '\-\-no-window-controls' "never shows silicon's macOS-style window controls"
assert_logged $'wl-paste\t--type\ttext' "reads only the text clipboard, never an image"
assert_logged $'wl-copy\t--type\timage/png' "copies the rendered image to the clipboard"
assert_logged '^notify' "notifies when the image is ready"

if ! ls "$out_dir"/code-*.png >/dev/null 2>&1; then
  fail "saves the image into the screenshot directory" "$(ls -la "$out_dir")"
fi
pass "saves the image into the screenshot directory"

# --- A title dot that is not a filename must not be treated as a language ------

# A domain in a browser tab title, and a version number: both end in a dotted
# token that is not a file extension, and both must fall through to the picker
# rather than being handed to silicon as a language.
OMARCHY_TEST_TITLE="example.io — Search" \
  OMARCHY_TEST_CLIPBOARD="plain words here" OMARCHY_TEST_GUM_PICK="txt" run_capture_tty
refute_logged $'silicon\t.*-l\tio' "rejects a domain suffix from a window title"

OMARCHY_TEST_TITLE="Release notes v1.2.3" \
  OMARCHY_TEST_CLIPBOARD="plain words here" OMARCHY_TEST_GUM_PICK="txt" run_capture_tty
refute_logged $'silicon\t.*-l\t3' "rejects a version-number suffix from a window title"

# --- Empty clipboard is not an error -------------------------------------------

OMARCHY_TEST_TITLE="config.rs — omarchy" OMARCHY_TEST_CLIPBOARD="" run_capture
refute_logged '^silicon' "does not render when the clipboard is empty"

# --- Content heuristics when the title has no usable extension -----------------

OMARCHY_TEST_TITLE="ryu@omarchy: ~" \
  OMARCHY_TEST_CLIPBOARD='#!/bin/bash
echo hi' run_capture
assert_logged $'silicon\t.*-l\tsh' "reads a bash shebang when the title says nothing"
refute_logged '^gum' "does not prompt once the content identifies the language"

OMARCHY_TEST_TITLE="ryu@omarchy: ~" \
  OMARCHY_TEST_CLIPBOARD='#!/usr/bin/env python3
print(1)' run_capture
assert_logged $'silicon\t.*-l\tpy' "reads a python shebang"

OMARCHY_TEST_TITLE="ryu@omarchy: ~" \
  OMARCHY_TEST_CLIPBOARD='<?php echo 1;' run_capture
assert_logged $'silicon\t.*-l\tphp' "recognises a php open tag"

OMARCHY_TEST_TITLE="ryu@omarchy: ~" \
  OMARCHY_TEST_CLIPBOARD='package main

func main() {}' run_capture
assert_logged $'silicon\t.*-l\tgo' "recognises a go package clause"

# --- Picker fallback -----------------------------------------------------------

OMARCHY_TEST_TITLE="ryu@omarchy: ~" \
  OMARCHY_TEST_CLIPBOARD="SELECT 1;" OMARCHY_TEST_GUM_PICK="sql" run_capture_tty
assert_logged '^gum' "prompts when neither the title nor the content decides"
assert_logged $'silicon\t.*-l\tsql' "renders with the language picked in the prompt"

OMARCHY_TEST_TITLE="ryu@omarchy: ~" \
  OMARCHY_TEST_CLIPBOARD="SELECT 1;" OMARCHY_TEST_GUM_PICK="" OMARCHY_TEST_GUM_EXIT=1 run_capture_tty
refute_logged '^silicon' "treats a dismissed prompt as a cancel, not an error"

# gum can also exit 0 with an empty selection (filter cleared, enter pressed
# on no match); that must be treated the same as a dismissed prompt.
OMARCHY_TEST_TITLE="ryu@omarchy: ~" \
  OMARCHY_TEST_CLIPBOARD="SELECT 1;" OMARCHY_TEST_GUM_PICK="" run_capture_tty
refute_logged '^silicon' "treats an empty picker selection as a cancel, not an error"

# --- Output modes --------------------------------------------------------------

rm -f "$out_dir"/code-*.png
OMARCHY_TEST_TITLE="config.rs — omarchy" \
  OMARCHY_TEST_CLIPBOARD="let x = 1;" run_capture copy
assert_logged $'wl-copy\t--type\timage/png' "copy mode still reaches the clipboard"
if ls "$out_dir"/code-*.png >/dev/null 2>&1; then
  fail "copy mode leaves no file behind" "$(ls -la "$out_dir")"
fi
pass "copy mode leaves no file behind"

OMARCHY_TEST_TITLE="config.rs — omarchy" \
  OMARCHY_TEST_CLIPBOARD="let x = 1;" run_capture save
refute_logged '^wl-copy' "save mode does not touch the clipboard"
if ! ls "$out_dir"/code-*.png >/dev/null 2>&1; then
  fail "save mode writes the file" "$(ls -la "$out_dir")"
fi
pass "save mode writes the file"

# --- silicon can fail while still exiting 0 ------------------------------------

# Real silicon exits 0 and writes no file for an unsupported language, a
# broken theme, or a permission error saving the image, after printing a
# diagnostic to stderr. The artifact itself, not the exit code, must decide.
rm -f "$out_dir"/code-*.png
OMARCHY_TEST_TITLE="config.rs — omarchy" OMARCHY_TEST_CLIPBOARD="let x = 1;" \
  OMARCHY_TEST_SILICON_FAIL="Error: Cannot load the theme" run_capture
capture_rc=$CAPTURE_EXIT

if ls "$out_dir"/code-*.png >/dev/null 2>&1; then
  fail "leaves no image behind when silicon silently fails" "$(ls -la "$out_dir")"
fi
pass "leaves no image behind when silicon silently fails"

refute_logged 'Code image' "sends no success notification when silicon produced no file"
assert_logged "Cannot load the theme" "surfaces silicon's stderr in the failure notification"
assert_logged $'\-u\tcritical' "notifies at critical urgency on a silent silicon failure"

if (( capture_rc == 0 )); then
  fail "exits non-zero when silicon silently fails" "exit code was 0"
fi
pass "exits non-zero when silicon silently fails"

# --- No controlling terminal (Hyprland keybinding, menu action) ----------------

# Neither the title nor the content route below decide the language, so the
# real flow would need to prompt with gum — but there is no tty to prompt in.
OMARCHY_TEST_TITLE="ryu@omarchy: ~" OMARCHY_TEST_CLIPBOARD="SELECT 1;" \
  OMARCHY_CODE_FONT_SIZE=41 OMARCHY_CODE_PADDING=37 OMARCHY_CODE_CORNER_RADIUS=9 run_capture
capture_rc=$CAPTURE_EXIT

# The handoff must name an absolute path, not the bare command. The spawned
# terminal gets a fresh PATH, and a bare name leaves the user staring at an
# empty terminal reporting the executable was not found — with no notification,
# because xdg-terminal-exec itself succeeded.
assert_logged $'uwsm-app\t--\txdg-terminal-exec\t--app-id=org.omarchy.terminal\t-e\t/usr/bin/env\t.*'"$ROOT"$'/bin/omarchy-capture-code\tboth' \
  "hands off to a floating terminal by absolute path when no tty is available"

# uwsm-app passes only argv over the app daemon's fifo, so the relaunched
# process starts from the systemd user manager's environment. Every setting
# has to ride along as an explicit assignment or it is silently lost, and the
# picker — now the common path, since content is never guessed — would hand
# back a default-styled image no matter what the user configured.
assert_logged $'uwsm-app\t.*\tOMARCHY_CODE_FONT=Test Mono=41\t' \
  "carries the resolved font across the handoff"
assert_logged $'uwsm-app\t.*\tOMARCHY_CODE_PADDING=37\t' \
  "carries the padding across the handoff"
assert_logged $'uwsm-app\t.*\tOMARCHY_CODE_CORNER_RADIUS=9\t' \
  "carries the corner radius across the handoff"
assert_logged $'uwsm-app\t.*\tOMARCHY_SCREENSHOT_DIR='"$out_dir"$'\t' \
  "carries the output directory across the handoff"
refute_logged '^gum' "never tries to prompt gum directly without a controlling terminal"
refute_logged '^notify' "a successful handoff is silent"

if (( capture_rc != 0 )); then
  fail "exits cleanly after a successful handoff" "exit code was $capture_rc"
fi
pass "exits cleanly after a successful handoff"

# The handoff itself can fail (no terminal emulator, no compositor); that must
# still surface, rather than exiting silently like a cancelled picker would.
OMARCHY_TEST_TITLE="ryu@omarchy: ~" OMARCHY_TEST_CLIPBOARD="SELECT 1;" \
  OMARCHY_TEST_UWSM_EXIT=1 run_capture
capture_rc=$CAPTURE_EXIT

assert_logged '^notify' "notifies when the picker cannot be reached at all"
assert_logged $'\-u\tcritical' "the no-terminal failure is a critical notification"

if (( capture_rc == 0 )); then
  fail "exits non-zero when the handoff itself fails" "exit code was 0"
fi
pass "exits non-zero when the handoff itself fails"

# --- Theming -------------------------------------------------------------------

colors_file="$theme_dir/colors.toml"
cached_theme="$test_tmp/cache/omarchy/silicon.tmTheme"

cp "$ROOT/themes/nord/colors.toml" "$colors_file"
rm -f "$cached_theme"

OMARCHY_TEST_TITLE="config.rs" OMARCHY_TEST_CLIPBOARD="let x = 1;" run_capture
assert_logged "\-\-theme" "renders with a theme derived from the active Omarchy theme"
assert_logged "\-\-background" "renders with a background derived from the active theme, not silicon's lavender default"

[[ -f $cached_theme ]] || fail "caches the rendered theme" "$(ls -la "$test_tmp/cache/omarchy" 2>&1)"
pass "caches the rendered theme"

if grep -q '{{' "$cached_theme"; then
  fail "every placeholder resolves against a shipped theme" "$(grep -n '{{' "$cached_theme" | head)"
fi
pass "every placeholder resolves against a shipped theme"

# plistlib, not a generic XML parser: a .tmTheme declares Apple's DTD by URL, and
# a generic parser may try to fetch it, making the test depend on the network.
python3 -c "
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    theme = plistlib.load(f)
assert 'settings' in theme, 'plist has no settings array'
" "$cached_theme" 2>"$test_tmp/plist.err" ||
  fail "rendered theme parses as a plist" "$(cat "$test_tmp/plist.err")"
pass "rendered theme parses as a plist"

# The keyword entry's scope is now a comma-separated list (storage.type.function
# and storage.type.class join it), so match it as a list member rather than
# requiring an exact "<string>keyword</string>" line.
for scope in comment keyword string; do
  grep -qE "<string>$scope(,|</string>)" "$cached_theme" ||
    fail "rendered theme styles the $scope scope" "$(head -40 "$cached_theme")"
  pass "rendered theme styles the $scope scope"
done

# Corrected scopes must use the colours already chosen in vscode-theme.json.tpl,
# not the ones transcribed from the original (buggy) brief, so a screenshot
# matches what the user sees in their editor. These pin fix-round colour
# corrections against a regression, using nord's known hex values.
python3 -c "
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    theme = plistlib.load(f)
by_scope = {s['scope']: s['settings'] for s in theme['settings'] if 'scope' in s}
modifier = by_scope.get('storage.modifier', {})
assert modifier.get('foreground') == '#ebcb8b', \
    f\"expected nord's yellow, got {modifier.get('foreground')}\"
plain_type = by_scope.get('storage.type, entity.name.type', {})
assert plain_type.get('foreground') == '#ebcb8b', \
    f\"expected nord's yellow, got {plain_type.get('foreground')}\"
" "$cached_theme" 2>"$test_tmp/scope-color.err" ||
  fail "storage keywords no longer share keyword's colour" "$(cat "$test_tmp/scope-color.err")"
pass "storage keywords no longer share keyword's colour"

python3 -c "
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    theme = plistlib.load(f)
by_scope = {s['scope']: s['settings'] for s in theme['settings'] if 'scope' in s}
param = by_scope.get('variable.parameter, entity.name.variable.parameter, meta.function.parameter', {})
assert param.get('foreground') == '#88c0d0', \
    f\"expected nord's cyan, got {param.get('foreground')}\"
assert param.get('fontStyle') == 'italic', \
    f\"expected vscode's italic fontStyle, got {param.get('fontStyle')}\"
" "$cached_theme" 2>"$test_tmp/scope-color.err" ||
  fail "function parameters match vscode's italic cyan" "$(cat "$test_tmp/scope-color.err")"
pass "function parameters match vscode's italic cyan"

# storage.type.class/storage.type.function must join Keyword's bright_magenta
# (vscode-theme.json.tpl groups them with "keyword"), not stay grouped with
# plain storage.type's yellow: TextMate's longest-match means `fn`/`func`/
# `function`/`class` would otherwise render differently than the user's editor.
python3 -c "
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    theme = plistlib.load(f)
by_scope = {s['scope']: s['settings'] for s in theme['settings'] if 'scope' in s}
keyword = by_scope.get('keyword, storage.type.class, storage.type.function', {})
assert keyword.get('foreground') == '#b48ead', \
    f\"expected nord's bright_magenta, got {keyword.get('foreground')}\"
" "$cached_theme" 2>"$test_tmp/scope-color.err" ||
  fail "storage.type.class and storage.type.function join Keyword's colour" "$(cat "$test_tmp/scope-color.err")"
pass "storage.type.class and storage.type.function join Keyword's colour"

# Invalid must strike through, matching vscode-theme.json.tpl's rule.
python3 -c "
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    theme = plistlib.load(f)
by_scope = {s['scope']: s['settings'] for s in theme['settings'] if 'scope' in s}
invalid = by_scope.get('invalid, invalid.illegal', {})
assert invalid.get('fontStyle') == 'strikethrough', \
    f\"expected strikethrough, got {invalid.get('fontStyle')}\"
" "$cached_theme" 2>"$test_tmp/scope-color.err" ||
  fail "invalid text is struck through" "$(cat "$test_tmp/scope-color.err")"
pass "invalid text is struck through"

# The full carry-over from vscode-theme.json.tpl's tokenColors, so this can't
# silently regress back down to a hand-picked subset: exact scope count, a
# few of the specific scopes called out as "doing the visual work" (method
# calls, property access, operators, punctuation, JSON keys, escapes), and
# the fontStyle counts (bold/italic/strikethrough) all pinned to vscode's
# actual numbers.
python3 -c "
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    theme = plistlib.load(f)
scoped = [s for s in theme['settings'] if 'scope' in s]
assert len(scoped) == 81, f'expected 81 scoped entries, got {len(scoped)}'

joined_scopes = ' | '.join(s['scope'] for s in scoped)
for needle in [
    'entity.name.function.method',
    'meta.function-call',
    'variable.other.property',
    'variable.other.object.property',
    'keyword.operator',
    'punctuation.accessor',
    'constant.language.boolean',
    'variable.other.constant',
    'variable.other.enummember',
    'entity.other.attribute-name',
    'meta.decorator',
    'support.type.property-name',
    'constant.character.escape',
    'markup.heading',
]:
    assert needle in joined_scopes, f'missing scope: {needle}'

font_styles = [s['settings'].get('fontStyle') for s in scoped if 'fontStyle' in s['settings']]
assert font_styles.count('bold') == 2, f\"expected 2 bold entries, got {font_styles.count('bold')}\"
assert font_styles.count('italic') == 11, f\"expected 11 italic entries, got {font_styles.count('italic')}\"
assert font_styles.count('strikethrough') == 2, f\"expected 2 strikethrough entries, got {font_styles.count('strikethrough')}\"
" "$cached_theme" 2>"$test_tmp/scope-color.err" ||
  fail "carries the full tokenColors set across, not a subset" "$(cat "$test_tmp/scope-color.err")"
pass "carries the full tokenColors set across, not a subset"

# --- Rounded corners with a border in the theme's accent colour ----------------
#
# Still examining the log from the "renders with a theme..." run_capture
# above: nothing has truncated $log_file since.

assert_logged $'silicon\t.*--background\t#2e3440' \
  "backgrounds with the plain card colour, not a darker shade, so the padding is invisible"
assert_logged $'silicon\t.*--pad-horiz\t24' "tightens horizontal padding to 24"
assert_logged $'silicon\t.*--pad-vert\t24' "tightens vertical padding to 24"
assert_logged $'silicon\t.*-f\tTest Mono=32' \
  "renders in the system monospace font at the default size"
assert_logged '\-\-no-round-corner' "asks silicon for a plain rectangle so ImageMagick can round it instead"
assert_logged $'magick\t.*-stroke\t#81a1c1' "strokes the corners in the theme's accent colour"

# Only the four corner arcs are stroked. A full outline reads as a generic
# wrapped frame, which is what this replaced — so assert both that the arcs are
# drawn and that no stroked roundrectangle sneaks back in. The mask that rounds
# the image is a separate, unstroked draw and is matched separately below.
for angles in "180,270" "270,360" "0,90" "90,180"; do
  assert_logged $'magick\t.*arc .* '"$angles" "draws the ${angles} corner arc"
done
# The rounding mask legitimately draws a roundrectangle, but with `-stroke none`
# — it is a shape to fill, not an outline. Only a roundrectangle drawn with a
# real stroke colour would put a frame back around the card.
if grep $'^magick' "$log_file" | grep -F 'roundrectangle' |
  grep -qvF $'-stroke\tnone'; then
  fail "does not stroke a full outline around the card" "$(cat "$log_file")"
fi
pass "does not stroke a full outline around the card"

# The mask must be drawn unstroked, or its edge picks up a hard line that the
# downscale cannot smooth away.
assert_logged $'magick\t.*-stroke\tnone\t.*roundrectangle' \
  "draws the rounding mask as an unstroked shape"

if ! grep -q BORDERED "$out_dir"/code-*.png 2>/dev/null; then
  fail "the bordered image replaces silicon's plain rectangle" "$(ls -la "$out_dir")"
fi
pass "the bordered image replaces silicon's plain rectangle"

# magick failing (or being unavailable) must not fail the capture: silicon's
# unbordered image is still perfectly usable, and losing the capture over a
# cosmetic post-processing step would be worse.
rm -f "$out_dir"/code-*.png
OMARCHY_TEST_TITLE="config.rs" OMARCHY_TEST_CLIPBOARD="let x = 1;" \
  OMARCHY_TEST_MAGICK_FAIL=1 run_capture
capture_rc=$CAPTURE_EXIT

if grep -q BORDERED "$out_dir"/code-*.png 2>/dev/null; then
  fail "a failed border pass leaves silicon's plain image untouched" "$(ls -la "$out_dir")"
fi
pass "a failed border pass leaves silicon's plain image untouched"

if ! ls "$out_dir"/code-*.png >/dev/null 2>&1; then
  fail "the capture itself still succeeds when the border pass fails" "$(ls -la "$out_dir")"
fi
pass "the capture itself still succeeds when the border pass fails"

assert_logged '^notify' "still sends the normal success notification when the border pass fails"
refute_logged $'\-u\tcritical' "a failed border pass is not treated as a capture failure"

if (( capture_rc != 0 )); then
  fail "exits cleanly when only the cosmetic border pass fails" "exit code was $capture_rc"
fi
pass "exits cleanly when only the cosmetic border pass fails"

# An unchanged colors.toml must not trigger a re-render.
before=$(stat -c %Y "$cached_theme")
sleep 1
OMARCHY_TEST_TITLE="config.rs" OMARCHY_TEST_CLIPBOARD="let x = 1;" run_capture
if (( before != $(stat -c %Y "$cached_theme") )); then
  fail "reuses the cache while the theme is unchanged" "the cache was rewritten"
fi
pass "reuses the cache while the theme is unchanged"

# Switching themes rewrites colors.toml, which must invalidate the cache.
touch "$colors_file"
OMARCHY_TEST_TITLE="config.rs" OMARCHY_TEST_CLIPBOARD="let x = 1;" run_capture
if (( before == $(stat -c %Y "$cached_theme") )); then
  fail "re-renders after the active theme changes" "the cache was not refreshed"
fi
pass "re-renders after the active theme changes"

# A theme may ship its own file and win over the generated one.
printf 'override' >"$theme_dir/silicon.tmTheme"
OMARCHY_TEST_TITLE="config.rs" OMARCHY_TEST_CLIPBOARD="let x = 1;" run_capture
assert_logged "\-\-theme.*current/theme/silicon.tmTheme" "prefers a theme-provided silicon.tmTheme"
rm -f "$theme_dir/silicon.tmTheme"

# No active theme at all: still produce an image, with silicon's own default.
rm -f "$colors_file" "$cached_theme"
OMARCHY_TEST_TITLE="config.rs" OMARCHY_TEST_CLIPBOARD="let x = 1;" run_capture
refute_logged "\-\-theme" "falls back to silicon's built-in theme when no theme is available"
refute_logged "\-\-background" "omits a background flag entirely when no theme is available"
refute_logged '\-\-no-round-corner' "skips the border rather than inventing an accent colour when no theme is available"
refute_logged '^magick' "never invokes magick when no theme is available"
assert_logged '^silicon' "still produces an image without an Omarchy theme"

cp "$ROOT/themes/nord/colors.toml" "$colors_file"

# --- Cache writes are atomic ----------------------------------------------------

# Simulate a render killed mid-write (SIGKILL, OOM, session teardown): the `sed
# -f` call that fills the cache writes partial output, then dies before
# finishing. A correct implementation renders to a temp file and only renames
# it into place on success, so the kill leaves no trace at the cache path
# (rather than a truncated file with a fresh mtime that the -nt check would
# then treat as valid forever).
rm -f "$cached_theme"

write_stub sed "#!/bin/bash
if [[ \"\$1\" == \"-f\" ]]; then
  printf 'CORRUPT'
  kill -KILL \$\$
fi
exec /usr/bin/sed \"\$@\"
"

OMARCHY_TEST_TITLE="config.rs" OMARCHY_TEST_CLIPBOARD="let x = 1;" run_capture
rm -f "$stub_bin/sed"

if [[ -f $cached_theme ]] && grep -q CORRUPT "$cached_theme"; then
  fail "a killed render never leaves a corrupt file at the cache path" "$(cat "$cached_theme")"
fi
pass "a killed render never leaves a corrupt file at the cache path"

# The next run (real sed restored) must recover with a full, valid render
# rather than being stuck reusing a corrupt cache.
OMARCHY_TEST_TITLE="config.rs" OMARCHY_TEST_CLIPBOARD="let x = 1;" run_capture
if [[ ! -f $cached_theme ]] || grep -q '{{' "$cached_theme" || grep -q CORRUPT "$cached_theme"; then
  fail "recovers with a full render after a killed attempt" "$(cat "$cached_theme" 2>&1)"
fi
pass "recovers with a full render after a killed attempt"

# --- Configurable font, padding and corner radius -----------------------------

# silicon has its own config file, but these flags are passed explicitly and
# would override it, so the env vars are the only way a user can change them.
OMARCHY_TEST_TITLE="config.rs" OMARCHY_TEST_CLIPBOARD="let x = 1;" \
  OMARCHY_CODE_FONT="JetBrains Mono=34" OMARCHY_CODE_PADDING=40 \
  OMARCHY_CODE_CORNER_RADIUS=8 run_capture

assert_logged $'silicon\t.*-f\tJetBrains Mono=34' "honours OMARCHY_CODE_FONT"
assert_logged $'silicon\t.*--pad-horiz\t40' "honours OMARCHY_CODE_PADDING horizontally"
assert_logged $'silicon\t.*--pad-vert\t40' "honours OMARCHY_CODE_PADDING vertically"
assert_logged $'magick\t.*roundrectangle 0,0 [0-9]*,[0-9]* 32,32' \
  "honours OMARCHY_CODE_CORNER_RADIUS (8 x 4 supersample)"

# Defaults still apply when nothing is set.
OMARCHY_TEST_TITLE="config.rs" OMARCHY_TEST_CLIPBOARD="let x = 1;" run_capture
assert_logged $'silicon\t.*-f\tTest Mono=32' "defaults to the system font at size 32"
assert_logged $'silicon\t.*--pad-horiz\t24' "defaults to 24px padding"

# The font follows `omarchy font set` the same way the colours follow
# `omarchy theme set` — that is the whole point of not hardcoding a family.
OMARCHY_TEST_TITLE="config.rs" OMARCHY_TEST_CLIPBOARD="let x = 1;" \
  OMARCHY_TEST_FONT="CaskaydiaCove Nerd Font" run_capture
assert_logged $'silicon\t.*-f\tCaskaydiaCove Nerd Font=32' \
  "follows the system font when it changes"

# Size is its own knob so changing it does not mean pinning a family and
# losing that tracking.
OMARCHY_TEST_TITLE="config.rs" OMARCHY_TEST_CLIPBOARD="let x = 1;" \
  OMARCHY_CODE_FONT_SIZE=18 run_capture
assert_logged $'silicon\t.*-f\tTest Mono=18' \
  "OMARCHY_CODE_FONT_SIZE resizes without pinning the family"

# silicon panics and writes nothing when handed an empty family, so a broken
# fontconfig must not reach it: fall back to the generic family, which
# fontconfig always resolves.
OMARCHY_TEST_TITLE="config.rs" OMARCHY_TEST_CLIPBOARD="let x = 1;" \
  OMARCHY_TEST_FONT="" run_capture
assert_logged $'silicon\t.*-f\tmonospace=32' \
  "falls back to the generic family when the system font is unknown"

# --- Content detection must not guess ------------------------------------------

# A miss costs one keypress; a wrong guess silently renders the snippet as the
# wrong language. These two both used to be mislabelled by inferential rules
# that have since been removed, so they are pinned here: C++ was read as
# TypeScript (`std::string` matched a type-annotation pattern) and Ruby as
# Python (both spell it `def`). Reaching the picker is the correct outcome.
for guessy in \
  'template <typename T>
std::optional<T> resolve(const std::map<std::string, T> &m) { return std::nullopt; }' \
  'class Palette
  def initialize(colors = {})
    @colors = colors
  end
end'; do
  OMARCHY_TEST_TITLE="ryu@omarchy: ~" OMARCHY_TEST_CLIPBOARD="$guessy" \
    OMARCHY_TEST_GUM_PICK="cpp" run_capture_tty
  assert_logged '^gum' "asks rather than guessing a language from ambiguous content"
done
