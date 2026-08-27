#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PATH="$ROOT/bin:$PATH"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mock_bin="$TMPDIR/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
set -euo pipefail

case "${1:-}" in
  dropbox-cli)
    [[ ${OMARCHY_TEST_DROPBOX_CLI:-0} == "1" ]]
    ;;
  tailscale)
    [[ ${OMARCHY_TEST_TAILSCALE_CLI:-0} == "1" ]]
    ;;
  netbird)
    [[ ${OMARCHY_TEST_NETBIRD_CLI:-0} == "1" ]]
    ;;
  *)
    command -v "${1:-}" >/dev/null 2>&1
    ;;
esac
SH

cat >"$mock_bin/dropbox-cli" <<'SH'
#!/bin/bash
set -euo pipefail

[[ ${OMARCHY_TEST_DROPBOX_RUNNING:-0} == "1" && ${1:-} == "running" ]]
SH

cat >"$mock_bin/tailscale" <<'SH'
#!/bin/bash
set -euo pipefail

[[ ${OMARCHY_TEST_TAILSCALE_STATUS:-0} == "1" && ${1:-} == "status" && ${2:-} == "--json" ]]
SH

cat >"$mock_bin/netbird" <<'SH'
#!/bin/bash
set -euo pipefail

[[ ${OMARCHY_TEST_NETBIRD_STATUS:-0} == "1" && ${1:-} == "status" && ${2:-} == "--json" ]]
SH

cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash
set -euo pipefail

# Answer for the unit actually asked about; both service checks reach for this
# same mock and must not see each other's state.
unit="${!#}"
case "$unit" in
  tailscaled.service)
    [[ ${OMARCHY_TEST_TAILSCALE_SYSTEMD:-0} == "1" ]]
    ;;
  netbird.service)
    [[ ${OMARCHY_TEST_NETBIRD_SYSTEMD:-0} == "1" ]]
    ;;
  *)
    exit 1
    ;;
esac
SH

cat >"$mock_bin/pgrep" <<'SH'
#!/bin/bash
set -euo pipefail

if (( $# == 0 )); then
  exit 1
fi

name="${!#}"
case "$name" in
  dropbox)
    [[ ${OMARCHY_TEST_DROPBOX_PROCESS:-0} == "1" ]]
    ;;
  tailscaled)
    [[ ${OMARCHY_TEST_TAILSCALE_PROCESS:-0} == "1" ]]
    ;;
  # The NetBird check matches the daemon's command line, because a plain
  # `netbird` process may just be the panel's own CLI poll.
  "netbird service run")
    [[ ${OMARCHY_TEST_NETBIRD_PROCESS:-0} == "1" ]]
    ;;
  netbird)
    echo "installed-service must not match bare netbird processes" >&2
    exit 2
    ;;
  *)
    exit 1
    ;;
esac
SH

# The check bounds its CLI probe with timeout(1), which macOS lacks; pass through.
cat >"$mock_bin/timeout" <<'SH'
#!/bin/bash
set -euo pipefail

shift
exec "$@"
SH

chmod +x "$mock_bin"/*
mock_path="$mock_bin:$ROOT/bin:$PATH"

PATH="$mock_path" OMARCHY_TEST_DROPBOX_CLI=1 OMARCHY_TEST_DROPBOX_RUNNING=1 omarchy-installed-service-dropbox
pass "installed Dropbox service check accepts running CLI"

PATH="$mock_path" OMARCHY_TEST_DROPBOX_PROCESS=1 omarchy-installed-service-dropbox
pass "installed Dropbox service check accepts running process"

if PATH="$mock_path" omarchy-installed-service-dropbox; then
  fail "installed Dropbox service check rejects unavailable service"
fi
pass "installed Dropbox service check rejects unavailable service"

PATH="$mock_path" OMARCHY_TEST_TAILSCALE_CLI=1 OMARCHY_TEST_TAILSCALE_STATUS=1 omarchy-installed-service-tailscale
pass "installed Tailscale service check accepts status JSON"

PATH="$mock_path" OMARCHY_TEST_TAILSCALE_SYSTEMD=1 omarchy-installed-service-tailscale
pass "installed Tailscale service check accepts active systemd service"

PATH="$mock_path" OMARCHY_TEST_TAILSCALE_PROCESS=1 omarchy-installed-service-tailscale
pass "installed Tailscale service check accepts running daemon"

if PATH="$mock_path" omarchy-installed-service-tailscale; then
  fail "installed Tailscale service check rejects unavailable service"
fi
pass "installed Tailscale service check rejects unavailable service"

PATH="$mock_path" OMARCHY_TEST_NETBIRD_CLI=1 OMARCHY_TEST_NETBIRD_STATUS=1 omarchy-installed-service-netbird
pass "installed NetBird service check accepts status JSON"

PATH="$mock_path" OMARCHY_TEST_NETBIRD_SYSTEMD=1 omarchy-installed-service-netbird
pass "installed NetBird service check accepts active systemd service"

PATH="$mock_path" OMARCHY_TEST_NETBIRD_PROCESS=1 omarchy-installed-service-netbird
pass "installed NetBird service check accepts running daemon"

if PATH="$mock_path" omarchy-installed-service-netbird; then
  fail "installed NetBird service check rejects unavailable service"
fi
pass "installed NetBird service check rejects unavailable service"

# The two checks share the systemctl and pgrep mocks, so a NetBird daemon must
# not make Tailscale look installed or the other way round.
if PATH="$mock_path" OMARCHY_TEST_NETBIRD_SYSTEMD=1 omarchy-installed-service-tailscale; then
  fail "installed Tailscale service check ignores a running NetBird daemon"
fi
pass "installed Tailscale service check ignores a running NetBird daemon"

if PATH="$mock_path" OMARCHY_TEST_TAILSCALE_SYSTEMD=1 omarchy-installed-service-netbird; then
  fail "installed NetBird service check ignores a running Tailscale daemon"
fi
pass "installed NetBird service check ignores a running Tailscale daemon"
