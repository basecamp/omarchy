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
exec_args=()
while (($# > 0)); do
  if [[ $1 == "--exec" ]]; then shift; exec_args=("$@"); break; fi
  shift
done
((${#exec_args[@]})) && echo "exec:${exec_args[*]}" >>"$TEST_LOG"
EOF
chmod +x "$test_bin/omarchy-notification-send"

# The shell runs the click command, so the invitation must not need a unit of its
# own to keep a blocked sender alive until the toast is answered.
cat >"$test_bin/systemd-run" <<'EOF'
#!/bin/bash
echo "systemd-run:$*" >>"$TEST_LOG"
EOF
chmod +x "$test_bin/systemd-run"

run_invitation_hook() {
  cp "$ROOT/install/user/first-run/install-voxtype.hook" "$hook_path"
  HOME="$test_home" PATH="$test_bin:$ROOT/bin:$PATH" TEST_LOG="$log_file" bash "$hook_path"
}

run_invitation_hook

[[ -f $test_home/.local/state/omarchy/done/voxtype-install-invitation ]] || fail "Voxtype invitation records completion"
[[ -f $hook_path ]] || fail "Voxtype invitation keeps its hook installed"
[[ $(grep -c '^notification$' "$log_file") -eq 1 ]] || fail "Voxtype invitation sends one notification"
grep -qx 'exec:omarchy-launch-floating-terminal-with-presentation omarchy-voxtype-install' "$log_file" ||
  fail "Voxtype invitation attaches the installer to the notification"
grep -q '^systemd-run:' "$log_file" && fail "Voxtype invitation needs no unit to hold an unanswered toast"

HOME="$test_home" PATH="$test_bin:$ROOT/bin:$PATH" TEST_LOG="$log_file" bash "$hook_path"

[[ -f $hook_path ]] || fail "completed Voxtype invitation keeps its hook installed"
[[ $(grep -c '^notification$' "$log_file") -eq 1 ]] || fail "completed Voxtype invitation hook does not notify again"

pass "Voxtype invitation only runs once"
