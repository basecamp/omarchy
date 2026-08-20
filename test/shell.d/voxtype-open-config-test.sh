#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_bin=$(mktemp -d)
log_file=$(mktemp)

cleanup() {
  rm -rf "$test_bin"
  rm -f "$log_file"
}
trap cleanup EXIT

cat >"$test_bin/omarchy-launch-floating-terminal-with-presentation" <<'EOF'
#!/bin/bash
echo "install:$*" >>"$TEST_LOG"
EOF
chmod +x "$test_bin/omarchy-launch-floating-terminal-with-presentation"

cat >"$test_bin/omarchy-voxtype-config" <<'EOF'
#!/bin/bash
echo "config" >>"$TEST_LOG"
EOF
chmod +x "$test_bin/omarchy-voxtype-config"

run_open_config() {
  local path=$1
  PATH="$path" TEST_LOG="$log_file" /bin/bash "$ROOT/bin/omarchy-voxtype-open-config"
}

# voxtype missing: use a PATH scoped to the stubs so a real voxtype
# elsewhere on the host (e.g. this dev machine) can't leak in.
run_open_config "$test_bin:$ROOT/bin"
[[ $(cat "$log_file") == "install:omarchy-voxtype-install" ]] ||
  fail "opens the installer when voxtype is missing" "$(cat "$log_file")"

: >"$log_file"

cat >"$test_bin/voxtype" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$test_bin/voxtype"

# voxtype present: only config runs, never the installer
run_open_config "$test_bin:$ROOT/bin"
[[ $(cat "$log_file") == "config" ]] ||
  fail "opens config when voxtype is installed" "$(cat "$log_file")"

pass "Voxtype open-config dispatches to the installer or config based on install state, never both"
