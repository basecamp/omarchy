#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command xdg-terminal-exec
require_command python3

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
systemctl_log="$test_tmp/systemctl.log"
host_path=$PATH
mkdir -p "$mock_bin" "$test_home/.config"

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_SYSTEMCTL_LOG"
exit 0
SH

cat >"$mock_bin/xdg-terminal-exec" <<'SH'
#!/bin/bash
if [[ $1 == "--print-id" ]]; then
  printf '%s\n' "${OMARCHY_TEST_PRINT_ID:-footclient.desktop}"
  exit 0
fi
exit 1
SH

chmod +x "$mock_bin"/*

export HOME="$test_home"
export OMARCHY_PATH="$ROOT"
export OMARCHY_TEST_SYSTEMCTL_LOG="$systemctl_log"
export PATH="$mock_bin:$ROOT/bin:$host_path"

OMARCHY_TEST_PRINT_ID=footclient.desktop
[[ $(omarchy-default-terminal) == "foot" ]] || fail "footclient.desktop reports as foot"
OMARCHY_TEST_PRINT_ID=foot.desktop
[[ $(omarchy-default-terminal) == "foot" ]] || fail "foot.desktop still reports as foot"
pass "omarchy-default-terminal treats footclient as foot"

: >"$systemctl_log"
omarchy-default-terminal foot >/dev/null
[[ -f $test_home/.local/share/applications/footclient.desktop ]] ||
  fail "setting foot installs the Omarchy footclient desktop file"
[[ $(grep -Ev '^\s*(#|$)' "$test_home/.config/xdg-terminals.list") == "footclient.desktop" ]] ||
  fail "setting foot prefers footclient" "$(cat "$test_home/.config/xdg-terminals.list")"
grep -Fq 'enable --now foot-server.socket' "$systemctl_log" ||
  fail "setting foot enables the foot server socket" "$(cat "$systemctl_log")"
pass "setting foot prefers footclient and starts the server"

printf '%s\n' "kitty.desktop" >"$test_home/.config/xdg-terminals.list"
rm -f "$test_home/.local/share/applications/footclient.desktop"
: >"$systemctl_log"
omarchy-default-terminal foot >/dev/null
[[ -f $test_home/.local/share/applications/footclient.desktop ]] ||
  fail "switching back to foot installs the Omarchy footclient desktop file"
[[ $(grep -Ev '^\s*(#|$)' "$test_home/.config/xdg-terminals.list") == "footclient.desktop" ]] ||
  fail "switching back to foot prefers footclient"
pass "switching back to foot from Kitty installs the Omarchy desktop"

data_home="$test_tmp/xdg-data"
config_home="$test_tmp/xdg-config"
mkdir -p "$data_home/applications" "$config_home"
cp "$ROOT/applications/footclient.desktop" "$data_home/applications/"
printf '%s\n' "footclient.desktop" >"$config_home/xdg-terminals.list"
cmd=$(
  PATH="$ROOT/bin:$host_path" \
    XDG_DATA_HOME="$data_home" \
    XDG_CONFIG_HOME="$config_home" \
    XDG_DATA_DIRS=/usr/share \
    xdg-terminal-exec --print-cmd --app-id=org.omarchy.btop --title=btop -e btop
)
[[ $cmd == *"--app-id=org.omarchy.btop"* ]] || fail "Omarchy footclient desktop passes --app-id" "$cmd"
[[ $cmd == *"omarchy-launch-foot"* ]] || fail "resolved command is the Foot wrapper" "$cmd"
pass "xdg-terminal-exec keeps org.omarchy app-ids through footclient"

wrapper_bin="$test_tmp/wrapper-bin"
mkdir -p "$wrapper_bin"
cat >"$wrapper_bin/footclient" <<'SH'
#!/bin/bash
printf 'footclient:%s\n' "$*"
SH
cat >"$wrapper_bin/foot" <<'SH'
#!/bin/bash
printf 'foot:%s\n' "$*"
SH
chmod +x "$wrapper_bin/footclient" "$wrapper_bin/foot"

got=$(
  PATH="$wrapper_bin:$mock_bin:$ROOT/bin:$host_path" \
    HOME="$test_tmp/bare-home" \
    XDG_RUNTIME_DIR="$test_tmp/empty-runtime" \
    WAYLAND_DISPLAY=wayland-test \
    omarchy-launch-foot --app-id=org.omarchy.btop -e btop
)
[[ $got == "foot:--app-id=org.omarchy.btop -e btop" ]] ||
  fail "wrapper falls back to standalone foot without a server socket" "$got"
pass "wrapper falls back to standalone foot without a server socket"

socket_runtime="$test_tmp/socket-runtime"
mkdir -p "$socket_runtime"
python3 - "$socket_runtime/foot-wayland-test.sock" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
s.listen(1)
PY
got=$(
  PATH="$wrapper_bin:$mock_bin:$ROOT/bin:$host_path" \
    HOME="$test_tmp/bare-home" \
    XDG_RUNTIME_DIR="$socket_runtime" \
    WAYLAND_DISPLAY=wayland-test \
    omarchy-launch-foot --app-id=org.omarchy.btop -e btop
)
[[ $got == "footclient:--app-id=org.omarchy.btop -e btop" ]] ||
  fail "wrapper uses footclient when the server socket exists" "$got"
pass "wrapper uses footclient when the server socket exists"

theme_home="$test_tmp/theme-home"
mkdir -p "$theme_home/.config/foot" "$theme_home/.local/state/omarchy/current/theme"
printf '%s\n' "font=TestFont:size=12" >"$theme_home/.config/foot/foot.ini"
printf '%s\n' "[colors-dark]" "background=000000" >"$theme_home/.local/state/omarchy/current/theme/foot.ini"
got=$(
  PATH="$wrapper_bin:$mock_bin:$ROOT/bin:$host_path" \
    HOME="$theme_home" \
    XDG_RUNTIME_DIR="$socket_runtime" \
    WAYLAND_DISPLAY=wayland-test \
    omarchy-launch-foot --app-id=org.omarchy.btop -e btop
)
[[ $got == "footclient:--override=include=$theme_home/.local/state/omarchy/current/theme/foot.ini --override=font=TestFont:size=12 --app-id=org.omarchy.btop -e btop" ]] ||
  fail "wrapper re-applies the live theme include and font" "$got"
pass "wrapper re-applies the live theme include and font"

migration="$ROOT/migrations/1786966072.sh"
run_migration() {
  HOME="$1" PATH="$mock_bin:$host_path" OMARCHY_PATH="$ROOT" \
    bash -euo pipefail "$migration" >/dev/null
}

mig_home="$test_tmp/mig-home"
mkdir -p "$mig_home/.config" "$mig_home/.local/share/applications"
printf '%s\n' "foot.desktop" >"$mig_home/.config/xdg-terminals.list"
: >"$systemctl_log"
run_migration "$mig_home"
[[ -f $mig_home/.local/share/applications/footclient.desktop ]] ||
  fail "migration installs the Omarchy footclient desktop file"
[[ $(grep -Ev '^\s*(#|$)' "$mig_home/.config/xdg-terminals.list") == "footclient.desktop" ]] ||
  fail "migration rewrites a stock foot list" "$(cat "$mig_home/.config/xdg-terminals.list")"
grep -Fq 'enable --now foot-server.socket' "$systemctl_log" ||
  fail "migration enables the foot server socket"
pass "migration upgrades a stock Foot install"

empty_home="$test_tmp/empty-home"
mkdir -p "$empty_home/.local/share/applications"
: >"$systemctl_log"
run_migration "$empty_home"
[[ ! -e $empty_home/.config/xdg-terminals.list ]] ||
  fail "migration does not create a user terminal list"
grep -Fq 'enable --now foot-server.socket' "$systemctl_log" ||
  fail "migration enables the foot server socket when there is no user list"
pass "migration leaves a missing user list to the packaged default"

kitty_home="$test_tmp/kitty-home"
mkdir -p "$kitty_home/.config"
printf '%s\n' "kitty.desktop" >"$kitty_home/.config/xdg-terminals.list"
: >"$systemctl_log"
run_migration "$kitty_home"
[[ $(<"$kitty_home/.config/xdg-terminals.list") == "kitty.desktop" ]] ||
  fail "migration leaves a non-Foot default alone"
[[ ! -e $kitty_home/.local/share/applications/footclient.desktop ]] ||
  fail "migration does not install a Foot desktop for Kitty"
[[ ! -s $systemctl_log ]] || fail "migration does not start the foot server for Kitty"
pass "migration leaves a non-Foot default alone"
