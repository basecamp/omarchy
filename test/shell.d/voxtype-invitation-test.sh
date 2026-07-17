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
echo action
EOF
chmod +x "$test_bin/omarchy-notification-send"

cat >"$test_bin/omarchy-launch-floating-terminal-with-presentation" <<'EOF'
#!/bin/bash
echo launch >>"$TEST_LOG"
EOF
chmod +x "$test_bin/omarchy-launch-floating-terminal-with-presentation"

run_invitation_hook() {
  cp "$ROOT/install/user/first-run/install-voxtype.hook" "$hook_path"
  HOME="$test_home" PATH="$test_bin:$ROOT/bin:$PATH" TEST_LOG="$log_file" bash "$hook_path"
}

run_invitation_hook

for _ in {1..50}; do
  [[ $(wc -l <"$log_file") -eq 2 ]] && break
  sleep 0.02
done

[[ -f $test_home/.local/state/omarchy/done/voxtype-install-invitation ]] || fail "Voxtype invitation records completion"
[[ -f $hook_path ]] || fail "Voxtype invitation keeps its hook installed"
[[ $(grep -c '^notification$' "$log_file") -eq 1 ]] || fail "Voxtype invitation sends one notification"
[[ $(grep -c '^launch$' "$log_file") -eq 1 ]] || fail "Voxtype invitation handles the notification action"

HOME="$test_home" PATH="$test_bin:$ROOT/bin:$PATH" TEST_LOG="$log_file" bash "$hook_path"
sleep 0.05

[[ -f $hook_path ]] || fail "completed Voxtype invitation keeps its hook installed"
[[ $(grep -c '^notification$' "$log_file") -eq 1 ]] || fail "completed Voxtype invitation hook does not notify again"
[[ $(grep -c '^launch$' "$log_file") -eq 1 ]] || fail "completed Voxtype invitation hook does not launch again"

pass "Voxtype invitation only runs once"
