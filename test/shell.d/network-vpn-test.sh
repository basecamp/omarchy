#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/nmcli" <<'EOF'
#!/bin/bash
case "$*" in
  *"connection show --active"*)
    printf 'vpn:Work VPN\nwifi:Home\n'
    ;;
  *"connection show"*)
    printf 'uuid-work:vpn:Work VPN\nuuid-home:802-11-wireless:Home\n'
    ;;
  *)
    printf '%s\n' "$*" >"${NMCLI_CALLS:?}"
    ;;
esac
EOF
chmod +x "$tmp/bin/nmcli"
export PATH="$tmp/bin:$PATH"
export NMCLI_CALLS="$tmp/calls"
export PATH="$ROOT/bin:$PATH"

assert_output() {
  local expected=$1
  shift
  local actual
  actual=$("$@")
  [[ "$actual" == "$expected" ]] || {
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  }
}

assert_output 'uuid-work:vpn:Work VPN' omarchy-network-vpn list
assert_output 'Work VPN' omarchy-network-vpn active
omarchy-network-vpn up 'Work VPN'
grep -Fx 'connection up Work VPN' "$NMCLI_CALLS" >/dev/null

pass "NetworkManager VPN helper lists, reports, and changes VPN connections"
