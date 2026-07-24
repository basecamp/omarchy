#!/bin/bash

source "$(dirname "$0")/base-test.sh"

# The hook guards on the real /etc/pam.d path, which can't be mocked via PATH.
if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]]; then
  pass "fingerprint invitation test skipped: host already has fingerprint auth configured"
  exit 0
fi

test_home=$(mktemp -d)
test_bin=$(mktemp -d)
log_file=$(mktemp)
hw_marker=$(mktemp -u)
hook_path="$test_home/.config/omarchy/hooks/post-update.d/setup-fingerprint.hook"

cleanup() {
  rm -rf "$test_home" "$test_bin"
  rm -f "$log_file" "$hw_marker"
}
trap cleanup EXIT

mkdir -p "$(dirname "$hook_path")"

cat >"$test_bin/omarchy-hw-fingerprint" <<'EOF'
#!/bin/bash
[[ -f $TEST_HW_MARKER ]]
EOF
chmod +x "$test_bin/omarchy-hw-fingerprint"

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

cat >"$test_bin/systemd-run" <<'EOF'
#!/bin/bash
echo "systemd-run:$*" >>"$TEST_LOG"
while (($# > 0)); do
  [[ $1 == "bash" ]] && exec "$@"
  shift
done
exit 1
EOF
chmod +x "$test_bin/systemd-run"

run_invitation_hook() {
  cp "$ROOT/install/user/first-run/setup-fingerprint.hook" "$hook_path"
  HOME="$test_home" PATH="$test_bin:$ROOT/bin:$PATH" TEST_LOG="$log_file" TEST_HW_MARKER="$hw_marker" bash "$hook_path"
}

run_invitation_hook

[[ ! -f $test_home/.local/state/omarchy/done/fingerprint-setup-invitation ]] || fail "fingerprint invitation stays pending without a reader"
[[ ! -s $log_file ]] || fail "fingerprint invitation does nothing without a reader"

touch "$hw_marker"
run_invitation_hook

[[ -f $test_home/.local/state/omarchy/done/fingerprint-setup-invitation ]] || fail "fingerprint invitation records completion"
[[ -f $hook_path ]] || fail "fingerprint invitation keeps its hook installed"
[[ $(grep -c '^systemd-run:' "$log_file") -eq 1 ]] || fail "fingerprint invitation uses a durable user service"
grep -q -- '--user --collect --quiet --service-type=exec --unit=omarchy-fingerprint-setup-invitation' "$log_file" || fail "fingerprint invitation configures its user service"
[[ $(grep -c '^notification$' "$log_file") -eq 1 ]] || fail "fingerprint invitation sends one notification"
[[ $(grep -c '^launch$' "$log_file") -eq 1 ]] || fail "fingerprint invitation handles the notification action"

HOME="$test_home" PATH="$test_bin:$ROOT/bin:$PATH" TEST_LOG="$log_file" TEST_HW_MARKER="$hw_marker" bash "$hook_path"

[[ $(grep -c '^systemd-run:' "$log_file") -eq 1 ]] || fail "completed fingerprint invitation does not schedule again"
[[ $(grep -c '^notification$' "$log_file") -eq 1 ]] || fail "completed fingerprint invitation hook does not notify again"

pass "fingerprint invitation waits for a reader and only runs once"
