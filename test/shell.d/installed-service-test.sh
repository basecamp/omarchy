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
  syncthing)
    [[ ${OMARCHY_TEST_SYNCTHING_CLI:-0} == "1" ]]
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

cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash
set -euo pipefail

case "$*" in
  "--user is-enabled --quiet syncthing.service")
    [[ ${OMARCHY_TEST_SYNCTHING_SYSTEMD:-0} == "1" ]]
    ;;
  *)
    [[ ${OMARCHY_TEST_TAILSCALE_SYSTEMD:-0} == "1" ]]
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
  *)
    exit 1
    ;;
esac
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

PATH="$mock_path" OMARCHY_TEST_SYNCTHING_CLI=1 OMARCHY_TEST_SYNCTHING_SYSTEMD=1 omarchy-installed-service-syncthing
pass "installed Syncthing service check accepts an enabled user service"

syncthing_home="$TMPDIR/syncthing-home"
mkdir -p "$syncthing_home/.local/state/syncthing"
touch "$syncthing_home/.local/state/syncthing/config.xml"
HOME="$syncthing_home" PATH="$mock_path" OMARCHY_TEST_SYNCTHING_CLI=1 omarchy-installed-service-syncthing
pass "installed Syncthing service check accepts an existing configuration while stopped"

community_home="$TMPDIR/community-home"
mkdir -p "$community_home/.config/omarchy"
printf '%s\n' '{"bar":{"layout":{"left":[],"center":[],"right":[{"id":"io.github.ilyazar.syncthing"}]}},"plugins":[]}' \
  >"$community_home/.config/omarchy/shell.json"
if HOME="$community_home" PATH="$mock_path" OMARCHY_TEST_SYNCTHING_CLI=1 OMARCHY_TEST_SYNCTHING_SYSTEMD=1 omarchy-installed-service-syncthing; then
  fail "installed Syncthing service check defers to a community widget"
fi
pass "installed Syncthing service check defers to a community widget"

if PATH="$mock_path" omarchy-installed-service-syncthing; then
  fail "installed Syncthing service check rejects an unavailable service"
fi
pass "installed Syncthing service check rejects an unavailable service"
