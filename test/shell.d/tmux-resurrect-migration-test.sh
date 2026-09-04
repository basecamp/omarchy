#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

test_home="$test_dir/home"
test_bin="$test_dir/bin"
package_log="$test_dir/packages.log"
restart_log="$test_dir/restarts.log"
tmux_config="$test_home/.config/tmux/tmux.conf"

mkdir -p "$test_home/.config/tmux" "$test_bin"
printf '%s\n' '# Personal tmux config' >"$tmux_config"

cat >"$test_bin/omarchy-pkg-add" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PACKAGE_LOG"
EOF
chmod +x "$test_bin/omarchy-pkg-add"

cat >"$test_bin/omarchy-restart-tmux" <<'EOF'
#!/bin/bash
printf 'restart\n' >>"$RESTART_LOG"
EOF
chmod +x "$test_bin/omarchy-restart-tmux"

run_migration() {
  HOME="$test_home" \
    PATH="$test_bin:$PATH" \
    PACKAGE_LOG="$package_log" \
    RESTART_LOG="$restart_log" \
    bash -euo pipefail "$ROOT/migrations/1786853363.sh"
}

run_migration

[[ $(<"$package_log") == 'tmux-resurrect' ]] || fail "tmux migration installs the resurrection engine"
grep -Fx '# Personal tmux config' "$tmux_config" >/dev/null || fail "tmux migration keeps personal configuration"
grep -Fx '# Persistent workspaces' "$tmux_config" >/dev/null || fail "tmux migration adds the resurrection block"
[[ $(<"$restart_log") == 'restart' ]] || fail "tmux migration reloads a running server"
pass "tmux migration installs resurrection without replacing configuration"

run_migration
[[ $(rg -c '^# Persistent workspaces$' "$tmux_config") == 1 ]] || fail "tmux migration does not duplicate the resurrection block"
pass "tmux migration is idempotent"
