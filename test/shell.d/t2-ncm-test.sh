#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
cat > "$test_tmp/bin/lspci" <<'EOF'
#!/bin/bash
if [[ ${TEST_T2:-0} == 1 ]]; then
  echo 'Bridge: Apple T2 [106b:1801]'
fi
for _ in {1..4096}; do echo 'Unrelated device [ffff:0000]'; done
EOF
cat > "$test_tmp/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_CALLS"
"$@"
EOF
chmod +x "$test_tmp/bin/"*
export PATH="$test_tmp/bin:$PATH" TEST_CALLS="$test_tmp/calls"
export OMARCHY_PATH="$ROOT" OMARCHY_T2_NCM_CONF="$test_tmp/conf/t2.conf"
migration="$ROOT/migrations/1788548210.sh"

TEST_T2=0 bash -euo pipefail "$migration"
[[ ! -e $OMARCHY_T2_NCM_CONF && ! -e $TEST_CALLS ]] || fail "non-T2 host changed"
pass "non-T2 hosts are untouched"

TEST_T2=1 bash -euo pipefail "$migration"
cmp "$ROOT/default/networkmanager/t2-ncm.conf" "$OMARCHY_T2_NCM_CONF"
[[ $(stat -c %a "$OMARCHY_T2_NCM_CONF") == 644 ]] || fail "wrong config mode"
[[ $(wc -l < "$TEST_CALLS") == 1 ]] || fail "unexpected privileged operations"
TEST_T2=1 bash -euo pipefail "$migration"
[[ $(wc -l < "$TEST_CALLS") == 1 ]] || fail "second invocation changed system"
pass "T2 migration installs once, without restarting networking"

printf '[main]\nno-auto-default=*\n' > "$OMARCHY_T2_NCM_CONF"
TEST_T2=1 bash -euo pipefail "$migration"
grep -Fxq 'no-auto-default=*' "$OMARCHY_T2_NCM_CONF" || fail "custom config overwritten"
[[ $(wc -l < "$TEST_CALLS") == 1 ]] || fail "custom config modified"
pass "customized configuration and saved connection profiles are preserved"

grep -Fxq 'no-auto-default+=mac:ac:de:48:00:11:22' "$ROOT/default/networkmanager/t2-ncm.conf" || fail "exclusion must append only the T2 address"
grep -Fq '"$OMARCHY_PATH/default/networkmanager/t2-ncm.conf"' "$ROOT/install/hardware/apple/fix-t2.sh" || fail "fresh installs missing exclusion"
pass "fresh installs share the narrowly scoped exclusion"
