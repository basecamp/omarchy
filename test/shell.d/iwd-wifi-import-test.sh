#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1784523021.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

bin="$test_tmp/bin"
iwd="$test_tmp/iwd"
nm="$test_tmp/nm"
mkdir -p "$bin" "$iwd" "$nm"

# sudo/systemctl/uuidgen stubs so the migration runs unprivileged. `sudo` just
# execs its arguments; the migration's own as_root() is exercised unchanged.
cat >"$bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH
cat >"$bin/systemctl" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$bin/uuidgen" <<'SH'
#!/bin/bash
echo "00000000-0000-0000-0000-00000000000$RANDOM"
SH

# nmcli stub: reports the SSIDs listed in $TEST_KNOWN_SSIDS as already-known
# wifi profiles, and records every invocation for later assertions.
cat >"$bin/nmcli" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_NMCLI_CALLS"
case "$*" in
  *"-f UUID,TYPE connection show"*)
    i=0
    while IFS= read -r s; do
      [[ -n $s ]] || continue
      echo "uuid-$i:802-11-wireless"
      i=$((i + 1))
    done <"$TEST_KNOWN_SSIDS"
    ;;
  *"-g 802-11-wireless.ssid connection show "*)
    uuid=${*: -1}
    sed -n "$((${uuid#uuid-} + 1))p" "$TEST_KNOWN_SSIDS"
    ;;
esac
exit 0
SH
chmod +x "$bin"/*

known="$test_tmp/known"
calls="$test_tmp/calls"
: >"$known"
: >"$calls"

printf 'Passphrase=hunter2hunter2\n' >"$iwd/HomeNet.psk"
printf '[Settings]\nHidden=true\n' >"$iwd/OpenCafe.open"
printf 'Passphrase=another-secret\n' >"$iwd/=4869C3A9.psk" # "Hié"
printf 'Identity=someone\n' >"$iwd/Campus.8021x"

run_migration() {
  PATH="$bin:$PATH" \
  OMARCHY_IWD_DIR="$iwd" \
  OMARCHY_NM_DIR="$nm" \
  TEST_KNOWN_SSIDS="$known" \
  TEST_NMCLI_CALLS="$calls" \
    bash -euo pipefail "$migration"
}

bash -n "$migration" || fail "iwd import migration parses"
pass "iwd import migration parses"

out=$(run_migration)

[[ -f $nm/HomeNet.nmconnection ]] || fail "migration imports a WPA-PSK network"
grep -Fx 'key-mgmt=wpa-psk' "$nm/HomeNet.nmconnection" >/dev/null || fail "PSK profile sets wpa-psk"
grep -Fx 'psk=hunter2hunter2' "$nm/HomeNet.nmconnection" >/dev/null || fail "PSK profile carries the passphrase"
grep -Fx 'ssid=HomeNet' "$nm/HomeNet.nmconnection" >/dev/null || fail "PSK profile sets the ssid"
pass "migration imports WPA-PSK networks"

[[ -f $nm/OpenCafe.nmconnection ]] || fail "migration imports an open network"
! grep -F 'wifi-security' "$nm/OpenCafe.nmconnection" >/dev/null || fail "open profile omits wifi-security"
grep -Fx 'hidden=true' "$nm/OpenCafe.nmconnection" >/dev/null || fail "open profile preserves hidden"
pass "migration imports open and hidden networks"

[[ -f $nm/Hié.nmconnection ]] || fail "migration decodes hex-encoded SSID filenames"
grep -Fx 'ssid=Hié' "$nm/Hié.nmconnection" >/dev/null || fail "hex-decoded profile sets the decoded ssid"
pass "migration decodes iwd's =<hex> SSID filenames"

[[ ! -f $nm/Campus.nmconnection ]] || fail "migration skips 802.1x enterprise networks"
pass "migration leaves 802.1x networks for manual re-add"

for f in "$nm"/*.nmconnection; do
  [[ $(stat -c '%a' "$f") == 600 ]] || fail "profile $f is written 0600"
done
pass "imported profiles are written 0600"

! grep -F 'hunter2hunter2' "$calls" >/dev/null || fail "PSK must never be passed to nmcli on argv"
! grep -F 'another-secret' "$calls" >/dev/null || fail "PSK must never be passed to nmcli on argv"
pass "secrets never reach nmcli's argv"

grep -F 'Imported 3 WiFi network(s)' <<<"$out" >/dev/null || fail "migration reports the import count"
pass "migration reports the import count"

# Second run with every SSID already known to NetworkManager must be a no-op.
printf 'HomeNet\nOpenCafe\nHié\n' >"$known"
rm -f "$nm"/*.nmconnection
out=$(run_migration)

[[ -z $(ls -A "$nm") ]] || fail "migration re-imports networks NetworkManager already knows"
! grep -F 'Imported' <<<"$out" >/dev/null || fail "migration reports an import when nothing was imported"
pass "migration is idempotent against existing NetworkManager profiles"
