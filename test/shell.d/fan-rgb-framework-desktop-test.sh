#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

fan_setter="$ROOT/bin/omarchy-theme-set-fan-framework-desktop"
fan_dispatcher="$ROOT/bin/omarchy-theme-set-fan"
install_script="$ROOT/install/hardware/framework/desktop-argb.sh"
migration="$ROOT/migrations/1785698076.sh"
sudoers_file="$ROOT/etc/sudoers.d/omarchy-framework-tool"

grep -F '%wheel ALL=(ALL) NOPASSWD: /usr/bin/framework_tool' "$sudoers_file" >/dev/null ||
  fail "sudoers rule allows passwordless framework_tool"

grep -F 'omarchy-pkg-add framework-system' "$install_script" >/dev/null ||
  fail "framework desktop install script installs the framework-system package"

! grep -F '/etc/sudoers.d/' "$install_script" >/dev/null ||
  fail "install script does not hand-write sudoers (package owns the rule)"

grep -F 'omarchy-pkg-add framework-system' "$migration" >/dev/null ||
  fail "migration installs the framework-system package for existing hardware"

grep -F '/etc/sudoers.d/omarchy-framework-tool' "$migration" >/dev/null ||
  fail "migration ensures the canonical sudoers rule"

grep -E '^# omarchy:summary=' "$fan_setter" >/dev/null ||
  fail "fan setter has command metadata summary"

grep -E '^# omarchy:summary=' "$fan_dispatcher" >/dev/null ||
  fail "fan dispatcher has command metadata summary"

grep -E '^# omarchy:summary=' "$ROOT/bin/omarchy-hw-framework-desktop" >/dev/null ||
  fail "framework desktop hardware detection has command metadata summary"

grep -F 'framework_tool' "$fan_setter" >/dev/null ||
  fail "fan setter invokes framework_tool"

! grep -F 'sudoers' "$fan_setter" >/dev/null ||
  fail "fan setter does not manage sudoers (relies on shipping rule)"
