#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

helper="$ROOT/bin/omarchy-terminal-open-link"
open_actions="$ROOT/config/kitty/open-actions.conf"
migration="$ROOT/migrations/1787852446.sh"

[[ -f $helper ]] || fail "Super+left ships the terminal link helper"
[[ -f $open_actions ]] || fail "Super+left ships the Kitty open-actions source"
[[ -f $migration ]] || fail "Super+left ships the open-actions migration"
pass "Super+left ships its helper, open-actions source, and migration"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# One case-insensitive rule claims exactly the local file URLs --
# file:///path and file://localhost/path -- anchored so file:/ with one slash
# or a host other than localhost matches nothing. Everything else keeps
# kitty's default behavior, including web and remote URLs.
(( $(grep -cxF 'url (?i:^file://(?:localhost)?/)' "$open_actions") == 1 )) ||
  fail "open-actions claims exactly one anchored local file URL rule"
[[ -z $(grep '^protocol ' "$open_actions" | grep -vxF 'protocol file') ]] ||
  fail "open-actions leaves web and remote URLs to kitty"

local_url_pattern=$(sed -n 's/^url //p' "$open_actions")
for url in file:///tmp/a file://localhost/tmp/a FILE:///tmp/a file://LOCALHOST/tmp/a; do
  grep -Pq "$local_url_pattern" <<<"$url" ||
    fail "open-actions matches local file URLs case-insensitively" "$url"
done
for url in file:/tmp/a file://remote/tmp/a file://localhost.example/tmp/a https://example.com/file:///tmp/a; do
  ! grep -Pq "$local_url_pattern" <<<"$url" ||
    fail "open-actions rejects non-local URL forms" "$url"
done
pass "open-actions claims only local file URLs"

# ${FILE_PATH} arrives percent-decoded, without query or fragment, as one
# argument. xdg-open does not accept a -- separator, so there is none.
(( $(grep -cxF 'action launch --type=background xdg-open ${FILE_PATH}' "$open_actions") == 1 )) ||
  fail "open-actions opens local files with xdg-open in the background and a single path argument"
grep -q -- 'xdg-open --' "$open_actions" &&
  fail "open-actions never passes -- to xdg-open"
pass "open-actions opens local files with xdg-open and a single path argument"

# The migration brings existing installs along: copy the shipped rules next to
# kitty.conf, and only when Kitty is configured and nothing custom would be
# clobbered.
migration_home="$TMPDIR/migration-home"
mkdir -p "$migration_home/.config/kitty"
cp "$ROOT/config/kitty/kitty.conf" "$migration_home/.config/kitty/kitty.conf"
HOME="$migration_home" OMARCHY_PATH="$ROOT" bash "$migration" >/dev/null ||
  fail "open-actions migration runs on an existing Kitty install"

cmp -s "$open_actions" "$migration_home/.config/kitty/open-actions.conf" ||
  fail "migration copies the shipped open-actions file verbatim"
pass "migration copies the shipped open-actions file verbatim"

before=$(find "$migration_home/.config" -type f -print0 | sort -z | xargs -0 sha256sum)
HOME="$migration_home" OMARCHY_PATH="$ROOT" bash "$migration" >/dev/null ||
  fail "open-actions migration runs a second time"
after=$(find "$migration_home/.config" -type f -print0 | sort -z | xargs -0 sha256sum)

[[ $before == "$after" ]] || fail "open-actions migration is idempotent"
pass "open-actions migration is idempotent"

custom_home="$TMPDIR/custom-home"
mkdir -p "$custom_home/.config/kitty"
cp "$ROOT/config/kitty/kitty.conf" "$custom_home/.config/kitty/kitty.conf"
cat >"$custom_home/.config/kitty/open-actions.conf" <<'EOF'
# Hand-written rules this user wants to keep
protocol file
url ^file://(localhost)?/
action launch --type=background my-open ${FILE_PATH}
EOF
custom_rules="$TMPDIR/custom-rules"
cp "$custom_home/.config/kitty/open-actions.conf" "$custom_rules"

HOME="$custom_home" OMARCHY_PATH="$ROOT" bash "$migration" >/dev/null ||
  fail "open-actions migration runs alongside a custom open-actions file"

cmp -s "$custom_rules" "$custom_home/.config/kitty/open-actions.conf" ||
  fail "migration leaves a custom open-actions file untouched"
pass "migration leaves a custom open-actions file untouched"
symlink_home="$TMPDIR/symlink-home"
mkdir -p "$symlink_home/.config/kitty"
cp "$ROOT/config/kitty/kitty.conf" "$symlink_home/.config/kitty/kitty.conf"
dangling_target="$TMPDIR/missing-open-actions"
ln -s "$dangling_target" "$symlink_home/.config/kitty/open-actions.conf"

HOME="$symlink_home" OMARCHY_PATH="$ROOT" bash "$migration" >/dev/null ||
  fail "open-actions migration runs alongside a dangling custom symlink"
[[ -L $symlink_home/.config/kitty/open-actions.conf ]] ||
  fail "migration preserves a dangling custom open-actions symlink"
[[ $(readlink "$symlink_home/.config/kitty/open-actions.conf") == "$dangling_target" ]] ||
  fail "migration leaves a dangling custom open-actions symlink unchanged"
[[ ! -e $dangling_target ]] ||
  fail "migration does not create the missing target of a custom symlink"
pass "migration preserves dangling custom open-actions symlinks"

bare_home="$TMPDIR/bare-home"
mkdir -p "$bare_home/.config/kitty"
HOME="$bare_home" OMARCHY_PATH="$ROOT" bash "$migration" >/dev/null ||
  fail "open-actions migration runs without a kitty.conf"
[[ ! -e $bare_home/.config/kitty/open-actions.conf ]] ||
  fail "migration installs nothing without kitty.conf"
pass "migration installs nothing without kitty.conf"

empty_home="$TMPDIR/empty-home"
mkdir -p "$empty_home"
HOME="$empty_home" OMARCHY_PATH="$ROOT" bash "$migration" >/dev/null ||
  fail "open-actions migration runs on a home without a config dir"
[[ -z $(find "$empty_home" -type f) ]] ||
  fail "migration leaves no files behind on a home without a config dir"
pass "migration leaves no files behind on a home without a config dir"

# The helper is what Super+left runs on a plain click. It must find the focused
# Kitty window itself, so everything it asks is stubbed and logged: hyprctl
# answers with a canned window, and kitten records its exact argv.
runtime_dir="$TMPDIR/runtime"
stub_bin="$TMPDIR/bin"
mkdir -p "$runtime_dir" "$stub_bin"

kitten_log="$TMPDIR/kitten-argv"
hyprctl_log="$TMPDIR/hyprctl-argv"

cat >"$stub_bin/kitten" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >>"$KITTEN_ARGV_LOG"
STUB
chmod +x "$stub_bin/kitten"

stub_activewindow() {
  cat >"$stub_bin/hyprctl" <<STUB
#!/bin/bash
printf '%s\n' "\$@" >>"\$HYPRCTL_ARGV_LOG"
printf '%s\n' '$1'
exit ${2:-0}
STUB
  chmod +x "$stub_bin/hyprctl"
}

run_helper() {
  KITTEN_ARGV_LOG="$kitten_log" HYPRCTL_ARGV_LOG="$hyprctl_log" \
    XDG_RUNTIME_DIR="$runtime_dir" PATH="$stub_bin:$PATH" \
    bash "$helper" 2>&1
}

# Every way the helper must refuse to click: no dispatch, no output, and still
# a zero exit -- a failed click must never surface as an error.
assert_never_dispatches() {
  local description="$1" output

  : >"$kitten_log"
  output=$(run_helper) || fail "$description"
  [[ -z $output ]] || fail "$description" "$output"
  [[ ! -s $kitten_log ]] || fail "$description" "$(paste -sd' ' "$kitten_log")"
  pass "$description"
}

stub_activewindow '{"class":"foot","pid":2718}'
assert_never_dispatches "helper ignores an active window that is not Kitty"

stub_activewindow '{"class":"kitty","pid":"not-a-number"}'
assert_never_dispatches "helper rejects a pid that is not numeric"

stub_activewindow '{"class":"kitty","title":"no pid field"}'
assert_never_dispatches "helper rejects a window without a pid"

stub_activewindow 'not json at all'
assert_never_dispatches "helper fails closed on malformed activewindow output"

# hyprctl prints "Invalid" and exits 1 when there is no active window.
stub_activewindow 'Invalid' 1
assert_never_dispatches "helper fails closed when no window is active"

# A plain file squatting on the socket's name is not a socket.
stub_activewindow '{"class":"kitty","pid":4711}'
touch "$runtime_dir/omarchy-kitty-4711"
assert_never_dispatches "helper requires a Unix socket, not just any file at the socket path"
rm "$runtime_dir/omarchy-kitty-4711"

# Everything below clicks through a real bound socket, and binding one is the
# only thing a sandbox may deny; treat the fixture as optional rather than fail
# there.
socket_bound=1
if command -v python3 >/dev/null; then
  python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' \
    "$runtime_dir/omarchy-kitty-31415" 2>/dev/null || socket_bound=0
else
  socket_bound=0
fi

if (( ! socket_bound )); then
  pass "cannot bind a Unix socket here; skipping the cases that need one"
  exit 0
fi

stub_activewindow '{"class":"kitty","pid":31415}'
: >"$kitten_log"
: >"$hyprctl_log"
output=$(run_helper) || fail "helper succeeds on an active Kitty window with a live socket"
[[ -z $output ]] || fail "helper is silent when it dispatches the click" "$output"

[[ $(cat "$hyprctl_log") == $'activewindow\n-j' ]] ||
  fail "helper asks hyprctl for the active window as JSON" "$(cat "$hyprctl_log")"

expected_argv="$TMPDIR/expected-kitten-argv"
printf '%s\n' @ --to "unix:$runtime_dir/omarchy-kitty-31415" \
  action --no-response --match state:focused mouse_handle_click link >"$expected_argv"
cmp -s "$expected_argv" "$kitten_log" ||
  fail "helper clicks the focused window's link over its own socket" "$(paste -sd' ' "$kitten_log")"
pass "helper clicks the link through the window's kitten socket"

# The socket alone is not permission: with a live socket in place the class
# still has to match exactly, or any window could click through a stray socket.
stub_activewindow '{"class":"Kitty","pid":31415}'
assert_never_dispatches "helper matches the Kitty class exactly even with a live socket"
