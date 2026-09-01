#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_path="$test_tmp/bin"
mkdir -p "$mock_path"

cat >"$mock_path/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_TMP/calls"
if [[ ${SUDO_FAIL:-} == 1 ]]; then
  exit 1
fi
exit 0
EOF

cat >"$mock_path/tailscale" <<'EOF'
#!/bin/bash
printf 'tailscale %s\n' "$*" >>"$TEST_TMP/calls"
EOF

cat >"$mock_path/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_TMP/calls"
EOF

cat >"$mock_path/omarchy-plugin-disable" <<'EOF'
#!/bin/bash
printf 'plugin-disable %s\n' "$*" >>"$TEST_TMP/calls"
EOF

cat >"$mock_path/omarchy-webapp-remove" <<'EOF'
#!/bin/bash
printf 'webapp-remove %s\n' "$*" >>"$TEST_TMP/calls"
EOF

cat >"$mock_path/omarchy-pkg-drop" <<'EOF'
#!/bin/bash
printf 'pkg-drop %s\n' "$*" >>"$TEST_TMP/calls"
EOF

chmod +x "$mock_path"/*

run_remove() {
  rm -f "$test_tmp/calls" "$test_tmp/out"
  PATH="$mock_path:$PATH" TEST_TMP="$test_tmp" \
    bash "$ROOT/bin/omarchy-remove-service-tailscale" >"$test_tmp/out" 2>&1 || return $?
}

status=0
SUDO_FAIL=1 run_remove || status=$?
(( status == 130 )) || fail "cancelled sudo exits 130 so the presentation wrapper skips Done" "status=$status"
[[ -e $test_tmp/calls ]] || fail "cancelled sudo still invokes sudo -v"
[[ $(<"$test_tmp/calls") == "sudo -v" ]] || fail "cancelled sudo does not tear Tailscale down" "$(<"$test_tmp/calls")"
if grep -q 'Tailscale has been removed.' "$test_tmp/out"; then
  fail "cancelled sudo does not claim Tailscale was removed" "$(<"$test_tmp/out")"
fi
pass "cancelled sudo aborts before teardown"

status=0
SUDO_FAIL=0 run_remove || status=$?
(( status == 0 )) || fail "authenticated sudo removes Tailscale" "status=$status"
expected=$'sudo -v\ntailscale down\nsystemctl --user disable --now omarchy-tailscale-receive.service\nsudo systemctl disable --now tailscaled.service\nplugin-disable omarchy.tailscale\nwebapp-remove Tailscale\npkg-drop tailscale'
[[ $(<"$test_tmp/calls") == "$expected" ]] || fail "authenticated sudo tears Tailscale down in order" "$(<"$test_tmp/calls")"
grep -qx 'Tailscale has been removed.' "$test_tmp/out" || fail "authenticated sudo reports Tailscale was removed" "$(<"$test_tmp/out")"
pass "authenticated sudo removes Tailscale"
