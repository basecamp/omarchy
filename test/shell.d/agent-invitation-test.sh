#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_home=$(mktemp -d)
test_bin=$(mktemp -d)
log_file=$(mktemp)
hook_path="$test_home/.config/omarchy/hooks/post-update.d/setup-agent.hook"

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

run_invitation_hook() {
  cp "$ROOT/install/user/first-run/setup-agent.hook" "$hook_path"
  HOME="$test_home" PATH="$test_bin:$ROOT/bin:$PATH" TEST_LOG="$log_file" bash "$hook_path"
}

run_invitation_hook

[[ -f $test_home/.local/state/omarchy/done/agent-setup-invitation ]] || fail "agent invitation records completion"
[[ -f $hook_path ]] || fail "agent invitation keeps its hook installed"
[[ $(grep -c '^notification$' "$log_file") -eq 1 ]] || fail "agent invitation sends one notification"
grep -qx 'exec:omarchy menu summon setup.default.agent' "$log_file" ||
  fail "agent invitation opens the agent defaults menu"

run_invitation_hook
[[ $(grep -c '^notification$' "$log_file") -eq 1 ]] || fail "completed agent invitation does not notify again"

pass "agent invitation only runs once"

# Someone who already chose an agent has nothing to be invited to, and must not
# burn the marker either -- otherwise clearing the choice later leaves them with
# no invitation and no default.
fresh_home=$(mktemp -d)
mkdir -p "$fresh_home/.config/omarchy/defaults"
printf 'claude\n' >"$fresh_home/.config/omarchy/defaults/agent"
: >"$log_file"
cp "$ROOT/install/user/first-run/setup-agent.hook" "$hook_path"
HOME="$fresh_home" PATH="$test_bin:$ROOT/bin:$PATH" TEST_LOG="$log_file" bash "$hook_path"

[[ ! -s $log_file ]] || fail "agent invitation stays quiet when a default is already set"
[[ ! -f $fresh_home/.local/state/omarchy/done/agent-setup-invitation ]] ||
  fail "agent invitation leaves its marker unset when a default is already set"
rm -rf "$fresh_home"

pass "agent invitation skips anyone who already chose an agent"
