#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/bin"

# Synthetic network used by every fixture below; nothing here is read from,
# or reflects, the machine running the test.
ssid="HomeNet"

# ── stub iw ──────────────────────────────────────────────────────────────────
# The iw stub cats a fixture file whose path is exported before each run.
printf '#!/bin/bash\ncat "$IW_FIXTURE"\n' > "$stage/bin/iw"
chmod +x "$stage/bin/iw"

# ── stub nmcli ───────────────────────────────────────────────────────────────
# Dispatches on the full argument list the real nm_get/nmcli calls produce.
cat > "$stage/bin/nmcli" <<STUB
#!/bin/bash
args="\$*"

case "\$args" in
  *-e\ no\ -g\ DEVICE,TYPE,STATE\ device\ status)
    printf 'wlo1:wifi:connected\n'
    ;;
  *-e\ no\ -g\ GENERAL.CONNECTION\ device\ show\ wlo1)
    printf '%s\n' "$ssid"
    ;;
  *-e\ no\ -g\ 802-11-wireless.band\ connection\ show\ "$ssid")
    printf '\n'
    ;;
  *-e\ no\ -g\ FREQ,SSID\ dev\ wifi\ list\ ifname\ wlo1\ --rescan\ no)
    printf '2412:%s\n5745:%s\n' "$ssid" "$ssid"
    ;;
  *)
    printf 'stub-nmcli: unexpected call: %s\n' "\$args" >&2
    exit 99
    ;;
esac
STUB
chmod +x "$stage/bin/nmcli"

# ── helper ───────────────────────────────────────────────────────────────────
run_band() {
  HOME="$stage" PATH="$stage/bin:$PATH" "$ROOT/bin/omarchy-network-band" 2>/dev/null
}

assert_band() {
  local label="$1" iw_text="$2" expect_band="$3" expect_available="$4" expect_mlo="${5:-0}"

  printf '%s\n' "$iw_text" > "$stage/iw-fixture"
  export IW_FIXTURE="$stage/iw-fixture"

  local output
  output=$(run_band) || fail "$label: omarchy-network-band exits 0" "$output"

  local got_band
  got_band=$(printf '%s' "$output" | awk -F'\t' '$1 == "band" { print $2 }')
  [[ $got_band == "$expect_band" ]] || fail "$label: reports correct band" "got=$got_band expected=$expect_band"

  local got_available
  got_available=$(printf '%s' "$output" | awk -F'\t' '$1 == "available" { print $2 }')
  [[ $got_available == "$expect_available" ]] || fail "$label: lists available bands" "got=$got_available expected=$expect_available"

  local got_selected
  got_selected=$(printf '%s' "$output" | awk -F'\t' '$1 == "selected" { print $2 }')
  [[ $got_selected == "auto" ]] || fail "$label: selected is auto" "got=$got_selected"

  local got_mlo
  got_mlo=$(printf '%s' "$output" | awk -F'\t' '$1 == "mlo" { print $2 }')
  [[ ${got_mlo:-0} == "$expect_mlo" ]] || fail "$label: reports MLO flag" "got=$got_mlo expected=$expect_mlo"

  pass "$label"
}

# ── MLO: two links (2.4 + 5 GHz) — should report the highest band ──────────
iw_mlo='Connected to 02:11:22:33:44:66 (on wlo1)
	SSID: HomeNet
	Link 0 BSSID 02:11:22:33:44:67
		freq: 2412.0
	Link 1 BSSID 02:11:22:33:44:68
		freq: 5745.0
MLD 02:11:22:33:44:66 stats:
	RX: 182119686 bytes (143468 packets)
	TX: 4658073 bytes (24069 packets)
	signal: -26 dBm
	tx bitrate: 1200.9 MBit/s 80MHz EHT-MCS 11 EHT-NSS 2 EHT-GI 0
	bss flags:
	dtim period: 1
	beacon int: 100'

assert_band "MLO reports 5 GHz (the highest-band link)" "$iw_mlo" "5" "2.4 5" "1"

# ── single 5 GHz link ────────────────────────────────────────────────────────
iw_single_5='Connected to 02:11:22:33:44:68 (on wlo1)
	SSID: HomeNet
	freq: 5745.0
	signal: -50 dBm
	rx bitrate: 1200.9 MBit/s 80MHz EHT-MCS 11 EHT-NSS 2 EHT-GI 0
	tx bitrate: 1200.9 MBit/s 80MHz EHT-MCS 11 EHT-NSS 2 EHT-GI 0'

assert_band "single 5 GHz link reports band 5" "$iw_single_5" "5" "2.4 5" "0"

# ── single 2.4 GHz link ─────────────────────────────────────────────────────
iw_single_24='Connected to 02:11:22:33:44:67 (on wlo1)
	SSID: HomeNet
	freq: 2412.0
	signal: -40 dBm
	tx bitrate: 286.8 MBit/s 40MHz VHT-MCS 7 VHT-NSS 2 VHT-GI 0.8'

assert_band "single 2.4 GHz link reports band 2.4" "$iw_single_24" "2.4" "2.4 5" "0"

# ── MLO: 5 + 6 GHz — should report 6 ───────────────────────────────────────
iw_mlo_56='Connected to 02:11:22:33:44:66 (on wlo1)
	SSID: HomeNet
	Link 0 BSSID 02:11:22:33:44:67
		freq: 5745.0
	Link 1 BSSID 02:11:22:33:44:68
		freq: 6115.0
MLD 02:11:22:33:44:66 stats:
	signal: -45 dBm
	tx bitrate: 2402.7 MBit/s 160MHz EHT-MCS 13 EHT-NSS 2 EHT-GI 0.8'

assert_band "MLO 5+6 GHz reports 6" "$iw_mlo_56" "6" "2.4 5 6" "1"
