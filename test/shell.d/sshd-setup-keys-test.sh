#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command ssh-keygen

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

invoker_home="$tmp_dir/home-invoker"
privileged_home="$tmp_dir/home-root"
mkdir -p "$invoker_home" "$privileged_home" "$tmp_dir/bin"

# A key ssh-keygen itself accepts, so the fixture cannot encode the answer.
ssh-keygen -q -t ed25519 -N '' -f "$tmp_dir/keypair" >/dev/null
key=$(cat "$tmp_dir/keypair.pub")

cat >"$tmp_dir/bin/sudo" <<'SCRIPT'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$TEST_LOG"
exit 0
SCRIPT

cat >"$tmp_dir/bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
printf 'pkg-add:%s\n' "$*" >>"$TEST_LOG"
SCRIPT

cat >"$tmp_dir/bin/omarchy-cmd-missing" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

cat >"$tmp_dir/bin/getent" <<EOF
#!/bin/bash
if [[ \$1 == passwd && ( \$2 == 4242 || \$2 == invoker ) ]]; then
  printf 'invoker:x:4242:4242:Invoker:%s\n' "$invoker_home"
  exit 0
fi
exit 2
EOF

chmod +x "$tmp_dir/bin/"*

export TEST_LOG="$tmp_dir/log"
log="$TEST_LOG"

# Launched through a privilege prompt, $HOME points at root while the keys
# belong to the user who started the setup (pkexec exposes their uid).
PATH="$tmp_dir/bin:$PATH" PKEXEC_UID=4242 HOME="$privileged_home" \
  bash "$ROOT/bin/omarchy-setup-security-sshd" --key="$key"

grep -Fxq 'pkg-add:openssh' "$log" || fail "sshd setup still installs the server" "$(cat "$log")"
grep -Fxq 'sudo:systemctl enable --now sshd.service' "$log" ||
  fail "sshd setup still enables the server before authorizing keys" "$(cat "$log")"

[[ -f $invoker_home/.ssh/authorized_keys ]] ||
  fail "sshd setup writes the key to the invoking user's authorized_keys" "$(cat "$log")"
grep -Fxq "$key" "$invoker_home/.ssh/authorized_keys" ||
  fail "sshd setup authorizes the passed key" "$(cat "$invoker_home/.ssh/authorized_keys")"
pass "sshd setup authorizes the invoking user's key"

if [[ -e $privileged_home/.ssh ]]; then
  fail "sshd setup leaves the privileged home untouched" "$(cat "$log")"
fi
pass "sshd setup leaves the privileged home untouched"