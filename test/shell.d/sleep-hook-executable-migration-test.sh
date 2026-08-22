#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1787336732.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin" "$test_dir/system-sleep"

# sudo runs the real command, so chmod acts on the redirected hook directory.
cat >"$test_dir/bin/sudo" <<'STUB'
#!/bin/bash

printf 'sudo %s\n' "$*" >>"$CALLS"
exec "$@"
STUB

# supergfxd answers with whatever mode the scenario sets, and like a daemon that
# is not running, stays silent when none is set.
cat >"$test_dir/bin/supergfxctl" <<'STUB'
#!/bin/bash

printf 'supergfxctl %s\n' "$*" >>"$CALLS"
[[ -n ${GPU_MODE:-} ]] || exit 1
echo "$GPU_MODE"
STUB

chmod +x "$test_dir/bin/"*

export CALLS="$test_dir/calls"

hook_dir="$test_dir/system-sleep"

install_hook() {
  printf '#!/bin/bash\n' >"$hook_dir/$1"
  chmod "$2" "$hook_dir/$1"
}

run_migration() {
  : >"$CALLS"

  OMARCHY_SYSTEM_SLEEP_DIR="$hook_dir" \
    PATH="$test_dir/bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

# Both hooks used to be copied in with cp -p from a 644 source, so an affected
# machine has non-executable copies that systemd-sleep never runs.
rm -f "$hook_dir"/*
install_hook keyboard-backlight 644
install_hook force-igpu 644
GPU_MODE=Integrated run_migration

[[ -x $hook_dir/keyboard-backlight ]] || fail "migration makes keyboard-backlight executable"
pass "migration makes keyboard-backlight executable"

[[ -x $hook_dir/force-igpu ]] || fail "migration makes force-igpu executable in Integrated mode"
pass "migration makes force-igpu executable in Integrated mode"

grep -qx 'supergfxctl -g' "$CALLS" ||
  fail "migration asks supergfxd for the GPU mode" "$(cat "$CALLS")"
pass "migration asks supergfxd for the GPU mode"

grep -qx "sudo chmod 755 $hook_dir/keyboard-backlight" "$CALLS" ||
  fail "migration changes the mode through sudo" "$(cat "$CALLS")"
pass "migration changes the mode through sudo"

# force-igpu forces Integrated mode after every sleep. The toggle removes it on
# the way to Hybrid, but a mode change made straight through supergfxctl leaves
# the inert copy behind, and waking it up would flip the GPU under the user.
rm -f "$hook_dir"/*
install_hook keyboard-backlight 644
install_hook force-igpu 644
GPU_MODE=Hybrid run_migration

[[ ! -x $hook_dir/force-igpu ]] || fail "migration leaves force-igpu inert in Hybrid mode"
pass "migration leaves force-igpu inert in Hybrid mode"

[[ -x $hook_dir/keyboard-backlight ]] || fail "migration still repairs keyboard-backlight in Hybrid mode"
pass "migration still repairs keyboard-backlight in Hybrid mode"

# With no answer from supergfxd the mode is unknown, so the hook stays as it is.
rm -f "$hook_dir"/*
install_hook force-igpu 644
run_migration

[[ ! -x $hook_dir/force-igpu ]] || fail "migration leaves force-igpu inert when supergfxd does not answer"
pass "migration leaves force-igpu inert when supergfxd does not answer"

(( $(grep -cx 'supergfxctl -g' "$CALLS") == 3 )) ||
  fail "migration retries the GPU mode query like the toggle does" "$(cat "$CALLS")"
pass "migration retries the GPU mode query like the toggle does"

# Hybrid-mode machines never install force-igpu, and hibernation setup is
# optional, so an absent hook is not an error.
rm -f "$hook_dir"/*
install_hook keyboard-backlight 644
run_migration

[[ -x $hook_dir/keyboard-backlight ]] || fail "migration repairs the hooks that are present"
pass "migration repairs the hooks that are present"

[[ ! -e $hook_dir/force-igpu ]] || fail "migration does not create a missing hook"
pass "migration does not create a missing hook"

# Migration completion is recorded per user, so a second account runs it again
# on a machine that is already repaired and must not need sudo for nothing.
install_hook force-igpu 755
GPU_MODE=Integrated run_migration

[[ ! -s $CALLS ]] ||
  fail "migration touches nothing on an already-repaired machine" "$(cat "$CALLS")"
pass "migration touches nothing on an already-repaired machine"

rm -f "$hook_dir"/*
run_migration

[[ ! -s $CALLS ]] ||
  fail "migration touches nothing when no hook is installed" "$(cat "$CALLS")"
pass "migration touches nothing when no hook is installed"
