#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mock_bin="$TMPDIR/bin"
calls="$TMPDIR/calls"
mkdir -p "$mock_bin" "$TMPDIR/home/.config/omarchy"

for command in omarchy-pkg-add omarchy-pkg-drop omarchy-plugin-enable omarchy-plugin-disable omarchy-launch-browser systemctl; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s %s\n' "$(basename "$0")" "$*" >>"$OMARCHY_TEST_CALLS"
SH
done

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
set -euo pipefail
[[ ${1:-} == "ufw" && ${OMARCHY_TEST_UFW:-0} != "1" ]]
SH

cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
set -euo pipefail
printf 'sudo %s\n' "$*" >>"$OMARCHY_TEST_CALLS"
if [[ $* == "ufw status" && -n ${OMARCHY_TEST_UFW_STATUS:-} ]]; then
  printf '%s\n' "$OMARCHY_TEST_UFW_STATUS"
fi
SH

cat >"$mock_bin/curl" <<'SH'
#!/bin/bash
set -euo pipefail
[[ ${OMARCHY_TEST_CURL_READY:-0} == "1" ]]
SH

chmod +x "$mock_bin"/*
mock_path="$mock_bin:$ROOT/bin:$PATH"

HOME="$TMPDIR/home" PATH="$mock_path" OMARCHY_TEST_CALLS="$calls" OMARCHY_TEST_CURL_READY=1 OMARCHY_TEST_UFW=1 \
  "$ROOT/bin/omarchy-install-service-syncthing" >/dev/null
grep -Fqx 'omarchy-pkg-add syncthing' "$calls" || fail "Syncthing installer adds the package"
grep -Fqx 'systemctl --user enable --now syncthing.service' "$calls" || fail "Syncthing installer enables its user service"
grep -Fqx 'omarchy-plugin-enable omarchy.syncthing' "$calls" || fail "Syncthing installer enables its native panel"
grep -Fqx 'omarchy-launch-browser http://127.0.0.1:8384' "$calls" || fail "Syncthing installer opens the ready Web UI"
grep -Fqx 'sudo ufw allow syncthing comment omarchy-syncthing' "$calls" || fail "Syncthing installer opens its packaged firewall profile"
grep -Fqx 'sudo ufw reload' "$calls" || fail "Syncthing installer reloads UFW"
[[ -f $TMPDIR/home/.local/state/omarchy/syncthing-ufw-managed ]] || fail "Syncthing installer marks its firewall ownership"
pass "Syncthing installer wires package, service, panel, and first-run UI"

printf '%s\n' '{"bar":{"layout":{"left":[],"center":[],"right":[{"id":"io.github.ilyazar.syncthing"}]}},"plugins":[]}' \
  >"$TMPDIR/home/.config/omarchy/shell.json"
: >"$calls"
output=$(HOME="$TMPDIR/home" PATH="$mock_path" OMARCHY_TEST_CALLS="$calls" OMARCHY_TEST_CURL_READY=1 OMARCHY_TEST_UFW=1 OMARCHY_TEST_UFW_STATUS='syncthing ALLOW Anywhere' \
  "$ROOT/bin/omarchy-install-service-syncthing")
if grep -Fq 'omarchy-plugin-enable omarchy.syncthing' "$calls"; then
  fail "Syncthing installer avoids duplicate community widgets"
fi
[[ $output == *"io.github.ilyazar.syncthing"* ]] || fail "Syncthing installer names the community widget it preserved"
pass "Syncthing installer preserves an existing community widget"

: >"$calls"
HOME="$TMPDIR/home" PATH="$mock_path" OMARCHY_TEST_CALLS="$calls" OMARCHY_TEST_UFW=1 OMARCHY_TEST_UFW_STATUS='syncthing ALLOW Anywhere' \
  "$ROOT/bin/omarchy-remove-service-syncthing" >/dev/null
grep -Fqx 'systemctl --user disable --now syncthing.service' "$calls" || fail "Syncthing remover disables its user service"
grep -Fqx 'omarchy-plugin-disable omarchy.syncthing' "$calls" || fail "Syncthing remover disables its panel"
grep -Fqx 'omarchy-pkg-drop syncthing' "$calls" || fail "Syncthing remover drops the package"
grep -Fqx 'sudo ufw --force delete allow syncthing' "$calls" || fail "Syncthing remover closes its managed firewall profile"
[[ ! -f $TMPDIR/home/.local/state/omarchy/syncthing-ufw-managed ]] || fail "Syncthing remover clears its firewall marker"
pass "Syncthing remover unwires service and panel without deleting user data"
