#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

fan_setter="$ROOT/bin/omarchy-theme-set-fan-framework-desktop"
fan_dispatcher="$ROOT/bin/omarchy-theme-set-fan"
wrapper="$ROOT/bin/omarchy-framework-tool-rgb"
install_script="$ROOT/install/hardware/framework/desktop-argb.sh"
migration="$ROOT/migrations/1785698076.sh"
sudoers_file="$ROOT/etc/sudoers.d/omarchy-framework-tool"

grep -F '%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-framework-tool-rgb' "$sudoers_file" >/dev/null ||
  fail "sudoers rule grants passwordless access to the RGB wrapper only"

! grep -F 'NOPASSWD: /usr/bin/framework_tool' "$sudoers_file" >/dev/null ||
  fail "sudoers rule does not expose the raw framework_tool binary"

grep -F 'omarchy-pkg-add framework-system' "$install_script" >/dev/null ||
  fail "framework desktop install script installs the framework-system package"

! grep -F '/etc/sudoers.d/' "$install_script" >/dev/null ||
  fail "install script does not hand-write sudoers (package owns the rule)"

grep -F 'omarchy-pkg-add framework-system' "$migration" >/dev/null ||
  fail "migration installs the framework-system package for existing hardware"

grep -F '/etc/sudoers.d/omarchy-framework-tool' "$migration" >/dev/null ||
  fail "migration ensures the canonical sudoers rule"

grep -F 'sudo rm /etc/sudoers.d/framework-tool' "$migration" >/dev/null ||
  fail "migration removes the legacy raw-framework_tool rule so it cannot linger"

! grep -F 'sudo mv /etc/sudoers.d/framework-tool' "$migration" >/dev/null ||
  fail "migration does not rename the legacy rule (it would preserve stale raw content)"

grep -E '^# omarchy:summary=' "$fan_setter" >/dev/null ||
  fail "fan setter has command metadata summary"

grep -E '^# omarchy:summary=' "$fan_dispatcher" >/dev/null ||
  fail "fan dispatcher has command metadata summary"

grep -E '^# omarchy:summary=' "$ROOT/bin/omarchy-hw-framework-desktop" >/dev/null ||
  fail "framework desktop hardware detection has command metadata summary"

grep -E '^# omarchy:summary=' "$wrapper" >/dev/null ||
  fail "RGB wrapper has command metadata summary"

grep -F 'sudo omarchy-framework-tool-rgb' "$fan_setter" >/dev/null ||
  fail "fan setter invokes the RGB wrapper via sudo, not the raw tool"

! grep -F 'sudo framework_tool' "$fan_setter" >/dev/null ||
  fail "fan setter does not invoke the raw framework_tool via sudo"

! grep -F 'sudoers' "$fan_setter" >/dev/null ||
  fail "fan setter does not manage sudoers (relies on shipping rule)"

grep -F 'exec /usr/bin/framework_tool --rgbkbd 0' "$wrapper" >/dev/null ||
  fail "RGB wrapper forwards only the --rgbkbd operation"

grep -E '\$# != 10' "$wrapper" >/dev/null ||
  fail "RGB wrapper rejects argument counts other than exact 10"

grep -E '\^0x\[0-9a-fA-F\]\{6\}\$' "$wrapper" >/dev/null ||
  fail "RGB wrapper validates each color as 0xRRGGBB"
