#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CLI="$ROOT/bin/omarchy"
TMPDIR=""

export PATH="$ROOT/bin:$PATH"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_output_contains() {
  local description="$1"
  local output="$2"
  local expected="$3"

  if [[ $output != *"$expected"* ]]; then
    printf 'Expected output to contain: %s\n' "$expected" >&2
    printf 'Actual output:\n%s\n' "$output" >&2
    fail "$description"
  fi

  pass "$description"
}

cleanup() {
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

output=$("$CLI" --help)
assert_output_contains "main help renders" "$output" "Omarchy command center"
assert_output_contains "main help includes hardware group" "$output" "hw"
assert_output_contains "main help includes package group" "$output" "pkg"
if grep -Eq '^  [a-z0-9-]+[[:space:]].*\([0-9]+\)$' <<<"$output"; then
  fail "main help does not show group counts"
fi
pass "main help does not show group counts"

output=$("$CLI" commands)
assert_output_contains "commands lists documented commands" "$output" "omarchy theme set <theme-name>"

"$CLI" commands --json | jq -e '.ok == true and (.commands | length >= 200)' >/dev/null
pass "commands --json is valid JSON with full bin coverage"

"$CLI" commands --json | jq -e 'all(.commands[]; .summary != "undocumented")' >/dev/null
pass "all included commands have summaries"

"$CLI" commands --json | jq -e 'all(.commands[]; has("binary") and has("filename_route") and has("routes") and (has("legacy") | not) and (has("usage") | not) and (has("visibility") | not) and (has("mutates") | not) and (has("interactive") | not))' >/dev/null
pass "JSON uses binary/routes and omits legacy/usage/extra metadata"

"$CLI" commands --check >/dev/null
pass "commands --check passes"

"$CLI" commands --all >/dev/null
pass "commands --all does not crash"

"$CLI" commands --all --json | jq -e '.commands[] | select(.route == "omarchy hyprland window gaps toggle" and .summary != "undocumented")' >/dev/null
pass "fallback commands are inferred and documented"

"$CLI" commands --all --json | jq -e '.commands[] | select(.route == "omarchy dev benchmark")' >/dev/null
pass "benchmark command is discoverable in all commands"

"$CLI" commands --json | jq -e '.commands[] | select(.binary == "omarchy-pkg-add" and .route == "omarchy pkg add" and .filename_route == "omarchy pkg add" and (.routes | index("omarchy pkg add")))' >/dev/null
pass "JSON exposes direct pkg add route"

"$CLI" commands --json | jq -e '.commands[] | select(.binary == "omarchy-refresh-pacman" and .requires_sudo == true)' >/dev/null
pass "sudo metadata marks sudo commands"

output=$("$CLI" theme --help)
assert_output_contains "group help renders" "$output" "Theme commands"

output=$("$CLI" install --help)
assert_output_contains "install group help renders" "$output" "Install commands"
assert_output_contains "install group includes browser route" "$output" "omarchy install browser"

output=$("$CLI" install)
assert_output_contains "bare group renders help instead of picker" "$output" "Install commands"
assert_output_contains "bare group includes browser route" "$output" "omarchy install browser"

output=$("$CLI" toggle)
assert_output_contains "bare root command with children renders help" "$output" "Toggle commands"
assert_output_contains "bare toggle help includes child route" "$output" "omarchy toggle waybar"

output=$("$CLI" pkg --help)
assert_output_contains "package group includes pkg add fallback route" "$output" "omarchy pkg add <packages...>"

output=$("$CLI" restart --help)
assert_output_contains "restart group includes inferred commands" "$output" "omarchy restart btop"
assert_output_contains "restart group includes all restart commands" "$output" "omarchy restart wifi"

output=$("$CLI" hw --help)
assert_output_contains "hardware group help renders" "$output" "omarchy hw asus rog"
assert_output_contains "hardware group includes touchpad" "$output" "omarchy hw touchpad"

output=$("$CLI" hw asus)
assert_output_contains "partial hardware prefix renders matching commands" "$output" "omarchy hw asus rog"
assert_output_contains "partial hardware prefix includes nested match" "$output" "omarchy hw asus zenbook ux5406aa"

output=$("$CLI" menu --help)
assert_output_contains "menu group includes share fallback route" "$output" "omarchy menu share"

output=$("$CLI" share)
assert_output_contains "bare required-arg alias renders CLI help" "$output" "Usage:"
assert_output_contains "bare share help uses canonical route" "$output" "omarchy share <clipboard|file|folder> [path...]"

output=$("$CLI" menu share)
assert_output_contains "bare required-arg filename route renders CLI help" "$output" "omarchy share <clipboard|file|folder> [path...]"

output=$("$CLI" branch set)
assert_output_contains "bare required-choice route renders CLI help" "$output" "omarchy branch set <master|rc|dev>"

CLI="$CLI" python3 <<'PY'
import json
import os
import subprocess
import sys

cli = os.environ['CLI']
commands = json.loads(subprocess.check_output([cli, 'commands', '--json'], text=True))['commands']
by_group = {}
for command in commands:
  binary = command['binary']
  stem = binary.removeprefix('omarchy-')
  group = stem.split('-', 1)[0]
  filename_route = 'omarchy ' + stem.replace('-', ' ')
  by_group.setdefault(group, []).append((binary, filename_route, command['route']))

missing = []
for group, rows in sorted(by_group.items()):
  proc = subprocess.run([cli, group, '--help'], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
  output = proc.stdout + proc.stderr
  if proc.returncode != 0:
    missing.append((group, '<group-help-failed>', f'exit {proc.returncode}'))
    continue
  for binary, filename_route, canonical_route in rows:
    if filename_route not in output and canonical_route not in output and binary not in output:
      missing.append((group, binary, filename_route))

if missing:
  for row in missing:
    print('\t'.join(row), file=sys.stderr)
  sys.exit(1)
PY
pass "every filename-derived group help represents its bins"

output=$(timeout 5 "$CLI" theme set --help)
assert_output_contains "command help renders without executing" "$output" "Binary:"
assert_output_contains "theme set help names binary" "$output" "omarchy-theme-set"

output=$(timeout 5 "$CLI" update --help)
assert_output_contains "mutating command help does not execute target" "$output" "omarchy-update"
assert_output_contains "root command help shows related child commands" "$output" "omarchy update perform"

output=$("$CLI" screenshot --help)
assert_output_contains "root alias resolves to command help" "$output" "omarchy-capture-screenshot"

"$CLI" commands --json | jq -e '.commands[] | select(.binary == "omarchy-capture-screenshot") | .aliases | index("omarchy screenshot")' >/dev/null
pass "aliases are included in JSON metadata"

output=$("$CLI" pkg add --help)
assert_output_contains "pkg add help resolves" "$output" "omarchy-pkg-add"
assert_output_contains "pkg add help shows direct route" "$output" "omarchy pkg add <packages...>"

output=$("$CLI" system reboot --help)
assert_output_contains "system command help is safe" "$output" "omarchy-system-reboot"

output=$("$CLI" dev benchmark --repeat=1)
assert_output_contains "benchmark command runs" "$output" "Omarchy CLI benchmark"

"$CLI" theme list >/dev/null
pass "safe dispatch works for theme list"

"$CLI" theme current >/dev/null
pass "safe dispatch works for theme current"

"$CLI" font list >/dev/null
pass "safe dispatch works for font list"

"$CLI" font current >/dev/null
pass "safe dispatch works for font current"

for binary in \
  omarchy-update \
  omarchy-theme-set \
  omarchy-capture-screenshot \
  omarchy-system-reboot \
  omarchy-pkg-add; do
  [[ -x $ROOT/bin/$binary ]] || fail "binary is executable: $binary"
  pass "binary is executable: $binary"
done

while IFS= read -r binary_path; do
  header=$(awk '
    NR == 1 && /^#!/ { next }
    /^[[:space:]]*$/ { if (seen) print; next }
    /^[[:space:]]*#/ { seen=1; print; next }
    { exit }
  ' "$binary_path")

  grep -q '^# omarchy:summary=' <<<"$header" || fail "metadata summary is present: $binary_path"
  ! grep -q '^# omarchy:binary=' <<<"$header" || fail "metadata does not repeat inferred binary: $binary_path"
  ! grep -q '^# omarchy:args=$' <<<"$header" || fail "metadata does not include empty args: $binary_path"
  ! grep -Eq '^# omarchy:(legacy|usage|visibility|mutates|interactive)=' <<<"$header" || fail "metadata avoids removed fields: $binary_path"
  ! grep -Eq '^# omarchy:requires-sudo=false$' <<<"$header" || fail "metadata omits false booleans: $binary_path"
done < <(find "$ROOT/bin" -maxdepth 1 -type f -executable -name 'omarchy-*' | sort)
pass "all executable bins have slim self-documenting metadata"

TMPDIR=$(mktemp -d)
ln -s "$CLI" "$TMPDIR/omarchy"

{
  printf '#!/bin/bash\n\n'
  printf '# ordinary comments are fine\n'
  printf '# omarchy:this malformed line should be ignored\n'
  printf '# omarchy:group=weird\n'
  printf '# omarchy:name=test\n'
  printf '# omarchy:summary=Survives malformed metadata comments\n'
  printf '# omarchy:made-up=value\n'
  printf 'echo weird-ok\n'
} >"$TMPDIR/omarchy-weird-test"
chmod +x "$TMPDIR/omarchy-weird-test"

{
  printf '#!/bin/bash\n\n'
  printf '# a partial metadata header should not destroy fallback routing\n'
  printf '# omarchy:summary=Partial metadata keeps inferred route\n'
  printf '# omarchy:made-up=value\n'
  printf 'echo partial-ok\n'
} >"$TMPDIR/omarchy-partial-meta-test"
chmod +x "$TMPDIR/omarchy-partial-meta-test"

{
  printf '#!/bin/bash\n\n'
  printf 'echo body-metadata-ok\n'
  printf '# omarchy:group=wrong\n'
  printf '# omarchy:name=wrong\n'
} >"$TMPDIR/omarchy-body-metadata-test"
chmod +x "$TMPDIR/omarchy-body-metadata-test"

"$TMPDIR/omarchy" commands --all --json | jq -e '.commands[] | select(.route == "omarchy weird test" and .summary == "Survives malformed metadata comments")' >/dev/null
pass "unknown metadata values are non-fatal"

"$TMPDIR/omarchy" commands --all --json | jq -e '.commands[] | select(.route == "omarchy partial meta test" and .summary == "Partial metadata keeps inferred route")' >/dev/null
pass "partial metadata keeps inferred fallback route"

"$TMPDIR/omarchy" commands --all --json | jq -e '.commands[] | select(.route == "omarchy body metadata test" and .summary == "Run the body metadata test command")' >/dev/null
pass "metadata-looking comments after script body are ignored"

output=$("$TMPDIR/omarchy" weird test)
assert_output_contains "temporary metadata command dispatches" "$output" "weird-ok"

output=$("$TMPDIR/omarchy" partial meta test)
assert_output_contains "partial metadata command dispatches" "$output" "partial-ok"

output=$("$TMPDIR/omarchy" body metadata test)
assert_output_contains "body metadata command dispatches by filename" "$output" "body-metadata-ok"

# --- chrome-beta opt-in browser wiring -------------------------------------
# Covers the opt-in Google Chrome Beta channel added alongside chrome/brave/
# edge/firefox/zen. Help + metadata are assertion-only; default-browser is
# exercised with real execution against PATH stubs (no package installs, no
# sudo, no real xdg changes); menu/theme wiring is checked at the source level.

# 1. Install route: help text and JSON metadata expose chrome-beta.
output=$("$CLI" install browser --help)
assert_output_contains "install browser help lists chrome-beta arg" "$output" "chrome-beta"
assert_output_contains "install browser help shows chrome-beta example" "$output" "omarchy install browser chrome-beta"
"$CLI" commands --json | jq -e '.commands[] | select(.binary == "omarchy-install-browser") | (.args | contains("chrome-beta")) and (.examples | index("omarchy install browser chrome-beta"))' >/dev/null
pass "install-browser JSON args + examples include chrome-beta"

# 2. Remove route: help args and JSON metadata expose chrome-beta + sudo.
output=$("$CLI" remove browser --help)
assert_output_contains "remove browser help lists chrome-beta arg" "$output" "chrome-beta"
"$CLI" commands --json | jq -e '.commands[] | select(.binary == "omarchy-remove-browser") | (.args | contains("chrome-beta")) and .requires_sudo == true' >/dev/null
pass "remove-browser JSON args include chrome-beta and requires_sudo"

# 3. Default-browser bidirectional mapping (real execution, stubbed PATH).
BROWSER_STUBDIR=$(mktemp -d)
STUB_LOG="$BROWSER_STUBDIR/calls.log"

make_default_browser_stubs() {
  # $1 is the desktop id that `xdg-settings get` should report.
  : >"$STUB_LOG"
  cat >"$BROWSER_STUBDIR/xdg-settings" <<EOF
#!/bin/bash
if [[ "\$1" == "get" ]]; then echo "$1"; exit 0; fi
echo "xdg-settings \$*" >>"$STUB_LOG"
exit 0
EOF
  cat >"$BROWSER_STUBDIR/xdg-mime" <<EOF
#!/bin/bash
echo "xdg-mime \$*" >>"$STUB_LOG"
exit 0
EOF
  cat >"$BROWSER_STUBDIR/notify-send" <<EOF
#!/bin/bash
echo "notify-send \$*" >>"$STUB_LOG"
exit 0
EOF
  chmod +x "$BROWSER_STUBDIR/xdg-settings" "$BROWSER_STUBDIR/xdg-mime" "$BROWSER_STUBDIR/notify-send"
}

# Reverse: a chrome-beta desktop id reports back as chrome-beta.
make_default_browser_stubs "google-chrome-beta.desktop"
output=$(PATH="$BROWSER_STUBDIR:$PATH" "$ROOT/bin/omarchy-default-browser")
assert_output_contains "default-browser reports chrome-beta from google-chrome-beta.desktop" "$output" "chrome-beta"

# Negative guard: a plain chrome desktop id still reports chrome, not chrome-beta.
make_default_browser_stubs "google-chrome.desktop"
output=$(PATH="$BROWSER_STUBDIR:$PATH" "$ROOT/bin/omarchy-default-browser")
if [[ $output != "chrome" ]]; then
  printf 'Expected exactly "chrome", got: %s\n' "$output" >&2
  fail "default-browser maps google-chrome.desktop to chrome (not chrome-beta)"
fi
pass "default-browser maps google-chrome.desktop to chrome (not chrome-beta)"

# Forward: selecting chrome-beta sets the chrome-beta desktop id and names it.
make_default_browser_stubs "google-chrome.desktop"
PATH="$BROWSER_STUBDIR:$PATH" "$ROOT/bin/omarchy-default-browser" chrome-beta
log=$(cat "$STUB_LOG")
assert_output_contains "default-browser chrome-beta sets google-chrome-beta.desktop" "$log" "xdg-settings set default-web-browser google-chrome-beta.desktop"
assert_output_contains "default-browser chrome-beta notifies as Chrome Beta" "$log" "Chrome Beta is now the default browser"

rm -rf "$BROWSER_STUBDIR"

# 4. Invalid-arg usage strings list chrome-beta (no side effects on this path).
output=$("$ROOT/bin/omarchy-install-browser" bogus 2>&1 || true)
assert_output_contains "install-browser usage lists chrome-beta" "$output" "Usage:"
assert_output_contains "install-browser usage includes chrome-beta" "$output" "chrome-beta"
output=$("$ROOT/bin/omarchy-remove-browser" bogus 2>&1 || true)
assert_output_contains "remove-browser usage lists chrome-beta" "$output" "Usage:"
assert_output_contains "remove-browser usage includes chrome-beta" "$output" "chrome-beta"
output=$("$ROOT/bin/omarchy-default-browser" bogus 2>&1 || true)
assert_output_contains "default-browser usage lists chrome-beta" "$output" "Usage:"
assert_output_contains "default-browser usage includes chrome-beta" "$output" "chrome-beta"

# 5. Menu submenu wiring + arm ordering (source-level, glob-shadowing guard).
# Each browser submenu must carry a "Chrome Beta" label and a chrome-beta
# dispatch arm, and the specific *"Chrome Beta"* arm must precede the broader
# *Chrome* arm so the latter does not shadow the former.
assert_menu_arm_ordering() {
  local description="$1" func="$2" beta_arm="$3" chrome_arm="$4"
  local block beta_line chrome_line
  block=$(awk -v fn="$func" '
    $0 ~ "^" fn "\\(\\) \\{" { inblock=1 }
    inblock { print }
    inblock && /^\}/ { exit }
  ' "$ROOT/bin/omarchy-menu")

  if [[ $block != *"Chrome Beta"* ]]; then
    printf 'Function %s has no "Chrome Beta" label\n' "$func" >&2
    fail "$description"
  fi
  if [[ $block != *"$beta_arm"* ]]; then
    printf 'Function %s missing dispatch arm: %s\n' "$func" "$beta_arm" >&2
    fail "$description"
  fi
  beta_line=$(grep -nF -- "$beta_arm" <<<"$block" | head -n1 | cut -d: -f1)
  chrome_line=$(grep -nF -- "$chrome_arm" <<<"$block" | head -n1 | cut -d: -f1)
  if [[ -z $beta_line || -z $chrome_line ]]; then
    printf 'Function %s missing one of the arms (beta=%s chrome=%s)\n' "$func" "$beta_line" "$chrome_line" >&2
    fail "$description"
  fi
  if ((beta_line >= chrome_line)); then
    printf 'In %s the Chrome Beta arm (line %s) must precede the Chrome arm (line %s)\n' "$func" "$beta_line" "$chrome_line" >&2
    fail "$description"
  fi
  pass "$description"
}

assert_menu_arm_ordering \
  "install submenu wires Chrome Beta before Chrome" \
  "show_install_browser_menu" \
  'present_terminal "omarchy-install-browser chrome-beta"' \
  'present_terminal "omarchy-install-browser chrome"'

assert_menu_arm_ordering \
  "remove submenu wires Chrome Beta before Chrome" \
  "show_remove_browser_menu" \
  'present_terminal "omarchy-remove-browser chrome-beta"' \
  'present_terminal "omarchy-remove-browser chrome"'

assert_menu_arm_ordering \
  "default submenu wires Chrome Beta before Chrome" \
  "show_setup_default_browser_menu" \
  'omarchy-default-browser chrome-beta' \
  'omarchy-default-browser chrome '

# 6. theme-set-browser refreshes a running Chrome Beta (source-level).
if ! grep -qF 'refresh_running_browser chrome-beta google-chrome-beta' "$ROOT/bin/omarchy-theme-set-browser"; then
  printf 'Expected omarchy-theme-set-browser to refresh chrome-beta\n' >&2
  fail "theme-set-browser refreshes chrome-beta google-chrome-beta"
fi
pass "theme-set-browser refreshes chrome-beta google-chrome-beta"
