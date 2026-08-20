#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_home=$(mktemp -d)
test_bin=$(mktemp -d)
log_file=$(mktemp)
hook_path="$test_home/.config/omarchy/hooks/post-update.d/install-voxtype.hook"

cleanup() {
  rm -rf "$test_home" "$test_bin"
  rm -f "$log_file"
}
trap cleanup EXIT

mkdir -p "$(dirname "$hook_path")"

cat >"$test_bin/omarchy-notification-send" <<'EOF'
#!/bin/bash
echo notification >>"$TEST_LOG"
while (($# > 0)); do
  [[ $1 == "--exec" ]] && echo "exec:$2" >>"$TEST_LOG"
  shift
done
EOF
chmod +x "$test_bin/omarchy-notification-send"

# The shell runs the click command, so the invitation must not need a unit of its
# own to keep a blocked sender alive until the toast is answered.
cat >"$test_bin/systemd-run" <<'EOF'
#!/bin/bash
echo "systemd-run:$*" >>"$TEST_LOG"
EOF
chmod +x "$test_bin/systemd-run"

# Stub the presence check rather than the PATH: the hook needs the real
# coreutils, so a voxtype on the host (e.g. this dev machine) would otherwise
# decide the test.
cat >"$test_bin/omarchy-cmd-missing" <<'EOF'
#!/bin/bash
[[ -n $TEST_VOXTYPE_MISSING ]]
EOF
chmod +x "$test_bin/omarchy-cmd-missing"

run_invitation_hook() {
  local voxtype_missing=$1

  cp "$ROOT/install/user/first-run/install-voxtype.hook" "$hook_path"
  HOME="$test_home" PATH="$test_bin:$ROOT/bin:$PATH" TEST_LOG="$log_file" \
    TEST_VOXTYPE_MISSING="$voxtype_missing" bash "$hook_path"
}

run_invitation_hook ""

[[ -s $log_file ]] && fail "Voxtype invitation stays quiet when voxtype is installed" "$(cat "$log_file")"
[[ -f $test_home/.local/state/omarchy/done/voxtype-install-invitation ]] &&
  fail "Voxtype invitation keeps its one-time marker unspent while voxtype is installed"

run_invitation_hook 1

[[ -f $test_home/.local/state/omarchy/done/voxtype-install-invitation ]] || fail "Voxtype invitation records completion"
[[ -f $hook_path ]] || fail "Voxtype invitation keeps its hook installed"
[[ $(grep -c '^notification$' "$log_file") -eq 1 ]] || fail "Voxtype invitation sends one notification"
grep -qx 'exec:omarchy-launch-floating-terminal-with-presentation omarchy-voxtype-install' "$log_file" ||
  fail "Voxtype invitation attaches the installer to the notification"
grep -q '^systemd-run:' "$log_file" && fail "Voxtype invitation needs no unit to hold an unanswered toast"

HOME="$test_home" PATH="$test_bin:$ROOT/bin:$PATH" TEST_LOG="$log_file" \
  TEST_VOXTYPE_MISSING=1 bash "$hook_path"

[[ -f $hook_path ]] || fail "completed Voxtype invitation keeps its hook installed"
[[ $(grep -c '^notification$' "$log_file") -eq 1 ]] || fail "completed Voxtype invitation hook does not notify again"

pass "Voxtype invitation only runs once"
