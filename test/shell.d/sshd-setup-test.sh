#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

export TEST_LOG="$tmp_dir/calls"
export TEST_DROPIN="$tmp_dir/sshd-dropin"

# sudo runs nothing here; it records what it was asked to do, and captures the
# drop-in the setup pipes through tee.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

case "$1" in
tee)
  printf 'sudo tee %s\n' "$2" >>"$TEST_LOG"
  cat >"$TEST_DROPIN"
  ;;
test)
  exit 1
  ;;
*)
  printf 'sudo %s\n' "$*" >>"$TEST_LOG"
  ;;
esac
SH

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$TEST_LOG"
SH

cat >"$stub_bin/ufw" <<'SH'
#!/bin/bash
printf 'ufw %s\n' "$*" >>"$TEST_LOG"
SH

# The real ssh-keygen is not on every machine that runs the suite, and the key
# fixtures below only have to be accepted or rejected, not verified.
cat >"$stub_bin/ssh-keygen" <<'SH'
#!/bin/bash
key=$(cat)
printf 'ssh-keygen %s\n' "$key" >>"$TEST_LOG"
[[ $key == ssh-* ]] || exit 1
printf '256 SHA256:test %s (ED25519)\n' "$key"
SH

chmod +x "$stub_bin"/*
export PATH="$stub_bin:$ROOT/bin:$PATH"
export HOME="$tmp_dir/home"
mkdir -p "$HOME"

"$ROOT/bin/omarchy-setup-security-sshd" --key="ssh-ed25519 AAAATEST tester@omarchy" >/dev/null

grep -Fx 'PasswordAuthentication no' "$TEST_DROPIN" >/dev/null ||
  fail "sshd setup turns password authentication off" "$(cat "$TEST_DROPIN" 2>/dev/null)"
pass "sshd setup turns password authentication off"

grep -Fx 'KbdInteractiveAuthentication no' "$TEST_DROPIN" >/dev/null ||
  fail "sshd setup turns keyboard-interactive authentication off" "$(cat "$TEST_DROPIN")"
pass "sshd setup turns keyboard-interactive authentication off"

grep -F 'sudo tee /etc/ssh/sshd_config.d/' "$TEST_LOG" >/dev/null ||
  fail "sshd setup writes its config as an sshd_config.d drop-in" "$(cat "$TEST_LOG")"
pass "sshd setup writes its config as an sshd_config.d drop-in"

grep -qxF 'ssh-ed25519 AAAATEST tester@omarchy' "$HOME/.ssh/authorized_keys" ||
  fail "sshd setup authorizes the key it was given"
pass "sshd setup authorizes the key it was given"

# Nothing may listen or be reachable before a key is in place.
config_line=$(grep -n 'sudo tee /etc/ssh/sshd_config.d/' "$TEST_LOG" | head -1 | cut -d: -f1)
key_line=$(grep -n '^ssh-keygen ' "$TEST_LOG" | head -1 | cut -d: -f1)
start_line=$(grep -n 'systemctl enable --now sshd.service' "$TEST_LOG" | head -1 | cut -d: -f1)
firewall_line=$(grep -n 'ufw limit 22/tcp' "$TEST_LOG" | head -1 | cut -d: -f1)

[[ -n $config_line && -n $key_line && -n $start_line && -n $firewall_line ]] ||
  fail "sshd setup configures, authorizes, starts and opens the firewall" "$(cat "$TEST_LOG")"

(( config_line < start_line )) ||
  fail "sshd is configured key-only before it is started" "$(cat "$TEST_LOG")"
pass "sshd is configured key-only before it is started"

(( key_line < start_line && key_line < firewall_line )) ||
  fail "sshd starts and the port opens only after a key is authorized" "$(cat "$TEST_LOG")"
pass "sshd starts and the port opens only after a key is authorized"

# A machine that already had sshd running gets the drop-in only through a reload.
reload_line=$(grep -n 'systemctl reload sshd.service' "$TEST_LOG" | head -1 | cut -d: -f1)

[[ -n $reload_line ]] && (( config_line < reload_line )) ||
  fail "the key-only config is applied to a server an earlier run left running" "$(cat "$TEST_LOG")"
pass "the key-only config is applied to a server an earlier run left running"

# A key that never lands must leave the machine unreachable rather than
# listening with nothing to log in with.
: >"$TEST_LOG"
rm -rf "$HOME/.ssh"

if "$ROOT/bin/omarchy-setup-security-sshd" --key="not-a-key" >/dev/null 2>&1; then
  fail "sshd setup fails on a key it cannot validate"
fi

if grep -q 'systemctl enable --now sshd.service' "$TEST_LOG"; then
  fail "a rejected key leaves the ssh server stopped" "$(cat "$TEST_LOG")"
fi
pass "a rejected key leaves the ssh server stopped"

if grep -q 'ufw limit 22/tcp' "$TEST_LOG"; then
  fail "a rejected key leaves the firewall port closed" "$(cat "$TEST_LOG")"
fi
pass "a rejected key leaves the firewall port closed"
