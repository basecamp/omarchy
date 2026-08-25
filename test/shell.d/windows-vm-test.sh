#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

windows_vm_command="$ROOT/bin/omarchy-windows-vm"

rg -q '^    restart: "no"$' "$windows_vm_command" ||
  fail "Windows VM uses manual startup by default"
pass "Windows VM uses manual startup by default"

if rg -q '^    restart: unless-stopped$' "$windows_vm_command"; then
  fail "Windows VM does not restart automatically at boot"
fi
pass "Windows VM does not restart automatically at boot"

legacy_invocation='omarchy-windows-vm (install|remove|launch|start|stop|down|status|help|\[command\])'
if rg -n "$legacy_invocation" \
  "$windows_vm_command" \
  "$ROOT/default/omarchy/omarchy-menu.jsonc" \
  "$ROOT/manual/28-windows-vm.md"; then
  fail "Windows VM uses canonical user-facing commands"
fi
pass "Windows VM uses canonical user-facing commands"
