#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
add_log="$test_tmp/add"
mkdir -p "$mock_bin" "$test_home/.config/omarchy/plugins"

cat >"$mock_bin/omarchy-plugin-add" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_PLUGIN_ADD_LOG"
SH
chmod +x "$mock_bin/omarchy-plugin-add"

export HOME="$test_home"
export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_TEST_PLUGIN_ADD_LOG="$add_log"
export OMARCHY_PATH="$ROOT"

: >"$add_log"
omarchy-afk-plugin-install
[[ $(<"$add_log") == "https://git.mooglest.com/mooglest/omarchy-afk-monitor.git --enable --yes" ]] ||
  fail "AFK plugin installer clones and enables the monitor plugin" "$(<"$add_log")"
pass "AFK plugin installer clones and enables the monitor plugin"

mkdir -p "$test_home/.config/omarchy/plugins/lcavadas.afk-monitor"
: >"$add_log"
omarchy-afk-plugin-install
[[ ! -s $add_log ]] || fail "AFK plugin installer is a no-op when the plugin is already present"
pass "AFK plugin installer is a no-op when the plugin is already present"
