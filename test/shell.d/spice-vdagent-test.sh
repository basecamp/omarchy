#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command python3

agent="$ROOT/bin/omarchy-vdagent"
service="$ROOT/default/systemd/user/omarchy-vdagent.service"
hardware="$ROOT/install/hardware/spice-vdagent.sh"
first_run="$ROOT/install/user/first-run/spice-vdagent.sh"
migration="$ROOT/migrations/1787768303.sh"

AGENT="$agent" python3 <<'PY'
import os
import runpy
import struct

module = runpy.run_path(os.environ["AGENT"])
Agent = module["Agent"]


class MemoryConnection:
    def __init__(self, incoming=b""):
        self.incoming = bytearray(incoming)
        self.sent = bytearray()

    def recv(self, size):
        data = self.incoming[:size]
        del self.incoming[:size]
        return bytes(data)

    def sendall(self, data):
        self.sent.extend(data)


connection = MemoryConnection()
agent = Agent(connection)
payload = struct.pack("<iiiii", 1920, 1200, 0, 0, 0)
agent.send(module["GUEST_XORG_RESOLUTION"], 1920, 1200, payload)
header = struct.unpack("<IIII", connection.sent[:16])
assert header == (module["GUEST_XORG_RESOLUTION"], 1920, 1200, len(payload))
assert connection.sent[16:] == payload

incoming = struct.pack("<IIII", module["CLIPBOARD_GRAB"], 0, 0, 0)
connection = MemoryConnection(incoming)
agent = Agent(connection)
agent.run()
reply = struct.unpack("<IIII", connection.sent)
assert reply == (
    module["CLIPBOARD_REQUEST"],
    module["CLIPBOARD_SELECTION"],
    module["UTF8_TEXT"],
    0,
)
PY
pass "SPICE agent preserves udscs framing and host clipboard requests"

grep -qx '# omarchy:hidden=true' "$agent" || fail "SPICE agent stays out of user-facing CLI listings"
grep -qx 'ConditionEnvironment=WAYLAND_DISPLAY' "$service" || fail "SPICE agent starts only in a Wayland session"
grep -qx 'ConditionPathExists=/dev/virtio-ports/com.redhat.spice.0' "$service" || fail "SPICE agent starts only in matching guests"
grep -qx 'ExecStart=/usr/bin/omarchy-vdagent' "$service" || fail "SPICE unit runs the package-owned agent"
grep -qx 'Restart=always' "$service" || fail "SPICE agent reconnects after daemon socket closure"
pass "SPICE user unit is scoped to matching Wayland guests"

grep -qx 'spice-vdagent' "$ROOT/install/omarchy-other.packages" || fail "SPICE package is available in the offline ISO pool"
if grep -qx 'spice-vdagent' "$ROOT/install/omarchy-base.packages"; then
  fail "SPICE package is not installed on bare-metal systems"
fi
grep -Fq 'hardware/spice-vdagent.sh' "$ROOT/install/hardware/all.sh" || fail "SPICE hardware setup runs during installation"
grep -Fq 'first-run/spice-vdagent.sh' "$ROOT/bin/omarchy-provision-first-run" || fail "SPICE user agent is installed on first login"
pass "SPICE support is available offline but installed only for matching guests"

if [[ -e $ROOT/etc/systemd/system/spice-vdagentd.service.d/override.conf ]]; then
  fail "SPICE support does not ship a spice-vdagentd override"
fi
if grep -R -E 'ExecStart=.*spice-vdagentd.*(^|[[:space:]])-X([[:space:]]|$)' \
  "$ROOT/bin" "$ROOT/default" "$ROOT/install" "$ROOT/migrations" >/dev/null; then
  fail "SPICE support never disables daemon session integration with -X"
fi
pass "SPICE daemon remains unchanged and keeps cursor-safe session integration"

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
stub_bin="$test_root/bin"
log="$test_root/commands.log"
spice_port="$test_root/com.redhat.spice.0"
mkdir -p "$stub_bin" "$test_root/home"
touch "$spice_port" "$log"

cat >"$stub_bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash
printf 'pkg\t%s\n' "$*" >>"$SPICE_TEST_LOG"
STUB
cat >"$stub_bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl\t%s\n' "$*" >>"$SPICE_TEST_LOG"
if [[ $* == "--user is-enabled spice-vdagent.service" ]]; then
  echo masked
  exit 1
fi
if [[ $* == "--user is-active --quiet graphical-session.target" ]]; then
  exit 1
fi
if [[ $* == "--global is-enabled spice-vdagent.service" ]]; then
  if [[ ${SPICE_TEST_SETTLED:-0} == "1" ]]; then
    echo masked
  fi
  exit 1
fi
if [[ $* == "is-active --quiet spice-vdagentd.socket" ]]; then
  [[ ${SPICE_TEST_SETTLED:-0} == "1" ]]
  exit
fi
STUB
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo\t%s\n' "$*" >>"$SPICE_TEST_LOG"
"$@"
STUB
cat >"$stub_bin/pkill" <<'STUB'
#!/bin/bash
printf 'pkill\t%s\n' "$*" >>"$SPICE_TEST_LOG"
STUB
chmod +x "$stub_bin/omarchy-pkg-add" "$stub_bin/systemctl" "$stub_bin/sudo" "$stub_bin/pkill"

SPICE_TEST_LOG="$log" OMARCHY_SPICE_PORT="$spice_port" \
  PATH="$stub_bin:$PATH" bash -eE -c 'source "$1"' bash "$hardware"
grep -Fq $'pkg\tspice-vdagent' "$log" || fail "matching VM installs spice-vdagent"
grep -Fq $'systemctl\t--global mask spice-vdagent.service' "$log" || fail "matching VM masks only the stock session agent"
pass "hardware setup replaces the stock SPICE session agent"

SPICE_TEST_LOG="$log" OMARCHY_SPICE_PORT="$spice_port" OMARCHY_PATH="$ROOT" \
  HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/config" \
  PATH="$stub_bin:$PATH" bash "$first_run"
cmp -s "$service" "$test_root/config/systemd/user/omarchy-vdagent.service" || fail "first run installs the shipped SPICE unit"
grep -Fq $'systemctl\t--user enable --now omarchy-vdagent.service' "$log" || fail "first run enables and starts the SPICE agent"
pass "first login installs the package-owned SPICE unit template"

: >"$log"
SPICE_TEST_LOG="$log" OMARCHY_SPICE_PORT="$spice_port" OMARCHY_PATH="$ROOT" \
  HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/migration-config" \
  PATH="$stub_bin:$PATH" bash -euo pipefail "$migration"
grep -Fq $'pkg\tspice-vdagent' "$log" || fail "migration installs spice-vdagent"
grep -Fq $'sudo\tsystemctl --global mask spice-vdagent.service' "$log" || fail "migration masks the stock session agent"
grep -Fq $'sudo\tsystemctl start spice-vdagentd.socket' "$log" || fail "migration activates the daemon socket"
cmp -s "$service" "$test_root/migration-config/systemd/user/omarchy-vdagent.service" || fail "migration installs the shipped SPICE unit"
pass "existing SPICE guests migrate to the Wayland clipboard agent"

: >"$log"
SPICE_TEST_SETTLED=1 SPICE_TEST_LOG="$log" OMARCHY_SPICE_PORT="$spice_port" \
  OMARCHY_PATH="$ROOT" HOME="$test_root/home" \
  XDG_CONFIG_HOME="$test_root/migration-config" PATH="$stub_bin:$PATH" \
  bash -euo pipefail "$migration"
if grep -q $'^sudo\t' "$log"; then
  fail "settled machine-wide SPICE state does not prompt every user for sudo"
fi
pass "SPICE migration is machine-idempotent for additional users"

: >"$log"
SPICE_TEST_LOG="$log" OMARCHY_SPICE_PORT="$test_root/missing-port" \
  PATH="$stub_bin:$PATH" bash -eE -c 'source "$1"' bash "$hardware"
[[ ! -s $log ]] || fail "non-SPICE machines skip VM clipboard setup"
pass "non-SPICE machines remain untouched"
