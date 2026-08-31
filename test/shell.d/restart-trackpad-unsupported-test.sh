#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -r "$tmp_dir"' EXIT

# Fake an empty i2c driver glob and no intel_quicki2c module.
cat >"$tmp_dir/lsmod" <<'INNER'
#!/bin/bash
exit 0
INNER
cat >"$tmp_dir/sudo" <<'INNER'
#!/bin/bash
exit 0
INNER
chmod +x "$tmp_dir/lsmod" "$tmp_dir/sudo"

# Point the script's glob at an empty directory by running under a fake root
# is hard; instead wrap: create a copy that uses no matching devices.
export PATH="$tmp_dir:$PATH"

# Create a disposable copy that looks for devices under $tmp_dir
script="$tmp_dir/omarchy-restart-trackpad"
sed "s|/sys/bus/i2c/drivers/i2c_hid_acpi/i2c-\\*|$tmp_dir/no-such-i2c-\\*|g" \
  "$ROOT/bin/omarchy-restart-trackpad" >"$script"
chmod +x "$script"

if "$script" >/dev/null 2>"$tmp_dir/err"; then
  fail "restart-trackpad should fail when no supported driver is present"
fi
grep -F 'No supported trackpad driver' "$tmp_dir/err" >/dev/null ||
  fail "restart-trackpad should explain the unsupported driver case"

pass "restart-trackpad fails clearly when no supported driver is present"
