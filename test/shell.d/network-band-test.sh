#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

# iw escapes every byte of an SSID that is not printable ASCII, so a name with
# an accent in it arrives as \xNN even though nmcli prints the same name raw.
cat >"$stub_bin/iw" <<'SH'
#!/bin/bash

[[ $1 == "dev" && $3 == "link" ]] || exit 1

printf '%s\n' "Connected to 00:11:22:33:44:55 (on $2)"
printf '\t%s\n' "SSID: ${OMARCHY_TEST_IW_SSID:-Caf\\xc3\\xa9}"
printf '\t%s\n' "freq: ${OMARCHY_TEST_IW_FREQ:-5180}"
SH

cat >"$stub_bin/nmcli" <<'SH'
#!/bin/bash

args=("$@")
fields=""
for i in "${!args[@]}"; do
  if [[ ${args[i]} == "-g" ]]; then
    fields="${args[i + 1]}"
    break
  fi
done

case "$fields" in
DEVICE,TYPE,STATE)
  printf '%s\n' "wlan0:wifi:connected"
  ;;
GENERAL.CONNECTION)
  printf '%s\n' "Home"
  ;;
FREQ,SSID)
  printf '%s\n' "2412 MHz:${OMARCHY_TEST_NM_SSID:-Café}"
  printf '%s\n' "5180 MHz:${OMARCHY_TEST_NM_SSID:-Café}"
  printf '%s\n' "5745 MHz:Neighbour"
  ;;
802-11-wireless.band)
  printf '%s\n' ""
  ;;
esac
SH

chmod +x "$stub_bin"/*
export PATH="$stub_bin:$ROOT/bin:$PATH"

status=$("$ROOT/bin/omarchy-network-band")

expected=$'band\t5\navailable\t2.4 5\nselected\tauto'
[[ $status == "$expected" ]] ||
  fail "network band lists every band an escaped SSID answers on" "$(printf 'expected:\n%s\nactual:\n%s' "$expected" "$status")"
pass "network band lists every band an escaped SSID answers on"

# A plain ASCII SSID is printed identically by both tools and must keep working.
plain=$(OMARCHY_TEST_IW_SSID="Home" OMARCHY_TEST_NM_SSID="Home" "$ROOT/bin/omarchy-network-band")

[[ $plain == "$expected" ]] ||
  fail "network band still matches an unescaped SSID" "$(printf 'expected:\n%s\nactual:\n%s' "$expected" "$plain")"
pass "network band still matches an unescaped SSID"

# An SSID whose name only differs from another by its escaped bytes must not
# borrow that network's bands.
other=$(OMARCHY_TEST_NM_SSID="Cafe" "$ROOT/bin/omarchy-network-band")

expected_other=$'band\t5\navailable\t5\nselected\tauto'
[[ $other == "$expected_other" ]] ||
  fail "network band offers nothing a different SSID answers on" "$(printf 'expected:\n%s\nactual:\n%s' "$expected_other" "$other")"
pass "network band offers nothing a different SSID answers on"

if OMARCHY_TEST_NM_SSID="Cafe" "$ROOT/bin/omarchy-network-band" 2.4 2>/dev/null; then
  fail "network band refuses a band the network does not answer on"
fi
pass "network band refuses a band the network does not answer on"
