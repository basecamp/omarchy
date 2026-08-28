#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

runtime_root="$ROOT/native/plugin-runtime"
migration="$ROOT/migrations/1787937949.sh"

for directory in protocol-version host worker bridge tests; do
  [[ -f $runtime_root/$directory/CMakeLists.txt ]] ||
    fail "plugin runtime is missing its $directory build boundary"
done
pass "plugin runtime keeps native boundaries independently buildable"

grep -F 'contracts/${contract}/CMakeLists.txt' "$runtime_root/CMakeLists.txt" >/dev/null ||
  fail "contract owners must edit the shared root CMake file to land"
grep -F 'direct execution denied' "$runtime_root/worker/main.cpp" >/dev/null ||
  fail "worker skeleton does not fail closed before a trusted launcher exists"
grep -F 'return false;' "$runtime_root/bridge/PluginHostInfo.cpp" >/dev/null ||
  fail "bridge skeleton advertises plugin availability before a broker exists"
pass "native runtime skeleton remains fail-closed"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"

cat >"$scratch/bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
if [[ $* == "--user is-active --quiet graphical-session.target" ]]; then
  exit "${GRAPHICAL_SESSION_STATUS:-0}"
fi
EOF
chmod +x "$scratch/bin/systemctl"

SYSTEMCTL_LOG="$scratch/active.log" PATH="$scratch/bin:$PATH" bash -euo pipefail "$migration"
grep -Fx -- '--user daemon-reload' "$scratch/active.log" >/dev/null
grep -Fx -- '--user enable omarchy-plugin-host.service' "$scratch/active.log" >/dev/null
grep -Fx -- '--user start omarchy-plugin-host.service' "$scratch/active.log" >/dev/null

SYSTEMCTL_LOG="$scratch/active.log" PATH="$scratch/bin:$PATH" bash -euo pipefail "$migration"
(( $(grep -Fxc -- '--user enable omarchy-plugin-host.service' "$scratch/active.log") == 2 )) ||
  fail "plugin host migration is not safe to repeat"
pass "plugin host migration reloads, enables, and starts idempotently in a graphical session"

SYSTEMCTL_LOG="$scratch/inactive.log" GRAPHICAL_SESSION_STATUS=3 PATH="$scratch/bin:$PATH" bash -euo pipefail "$migration"
grep -Fx -- '--user enable omarchy-plugin-host.service' "$scratch/inactive.log" >/dev/null
grep -F -- '--user start omarchy-plugin-host.service' "$scratch/inactive.log" >/dev/null &&
  fail "plugin host migration starts outside a graphical session"
pass "plugin host migration enables without starting outside a graphical session"
