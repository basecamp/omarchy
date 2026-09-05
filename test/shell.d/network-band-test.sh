#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# omarchy-network-band reads the link with `iw dev <iface> link`. On a secondary
# Wi-Fi adapter iw prints a complete link report -- SSID and freq included --
# and then still exits non-zero, failing the signal-strength ioctl with
# "Operation not permitted". The script runs under `set -euo pipefail`, so
# taking that exit status at face value aborted before printing anything, and
# the panel's band section silently vanished for any adapter that was not the
# one holding the default route.

band_script="$ROOT/bin/omarchy-network-band"

stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT

# An `iw` that behaves like the real one on a secondary adapter: correct output
# on stdout, a diagnostic on stderr, and a non-zero exit.
cat >"$stub_dir/iw" <<'STUB'
#!/bin/bash
echo "command failed: Operation not permitted (-1)" >&2
cat <<'OUT'
Connected to b8:fb:b3:ea:61:70 (on wlp3s0)
	SSID: TestNet
	freq: 5180.0
OUT
exit 255
STUB
chmod +x "$stub_dir/iw"

# nmcli stub: the device has an active profile, no band pinned, and the SSID is
# visible on both bands so `available` carries more than one entry.
#
# Field order matters: available_bands() asks for FREQ,SSID (frequency first,
# SSID last so an SSID containing ':' can be reassembled), so the stub must
# emit "<freq>:<ssid>" and not the reverse.
cat >"$stub_dir/nmcli" <<'STUB'
#!/bin/bash
args="$*"
case "$args" in
  *GENERAL.CONNECTION*) echo "TestProfile" ;;
  *802-11-wireless.band*) echo "" ;;
  *FREQ,SSID*)
    printf '2457 MHz:TestNet\n'
    printf '5180 MHz:TestNet\n'
    ;;
  *DEVICE,TYPE,STATE*) printf 'wlp3s0:wifi:connected\n' ;;
  *) : ;;
esac
exit 0
STUB
chmod +x "$stub_dir/nmcli"

status=0
output=$(PATH="$stub_dir:$PATH" bash "$band_script" --iface wlp3s0 2>/dev/null) || status=$?

if (( status == 0 )); then
  pass "omarchy-network-band survives iw exiting non-zero on a secondary adapter"
else
  fail "omarchy-network-band survives iw exiting non-zero on a secondary adapter" \
    "exited with status $status"
fi

# An empty report is indistinguishable from "no band control" in the panel,
# which is exactly how the bug presented.
if [[ -n $output ]]; then
  pass "omarchy-network-band prints a report rather than aborting under set -e"
else
  fail "omarchy-network-band prints a report rather than aborting under set -e" \
    "no output produced"
fi

if [[ $output == *"band	5"* ]]; then
  pass "omarchy-network-band reports the band parsed from a non-zero iw run"
else
  fail "omarchy-network-band reports the band parsed from a non-zero iw run" \
    "output was: $output"
fi

# The panel only renders its band section when more than one band is available.
if [[ $output == *"available	2.4 5"* ]]; then
  pass "omarchy-network-band still enumerates available bands after a non-zero iw run"
else
  fail "omarchy-network-band still enumerates available bands after a non-zero iw run" \
    "output was: $output"
fi
