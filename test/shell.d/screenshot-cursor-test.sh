#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin" "$tmp_dir/shots"

export OMARCHY_TEST_CALLS="$tmp_dir/calls"
: >"$OMARCHY_TEST_CALLS"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "getoption" ]]; then
  printf '%s\n' '{"option":"cursor:no_hardware_cursors","int":1,"set":true}'
  exit 0
fi

printf 'hyprctl %s\n' "$*" >>"$OMARCHY_TEST_CALLS"
SH

cat >"$stub_bin/omarchy-capture-region" <<'SH'
#!/bin/bash

printf 'pick %s\n' "$*" >>"$OMARCHY_TEST_CALLS"
printf '\n'
printf '%s\n' "0,0 100x100"
SH

cat >"$stub_bin/grim" <<'SH'
#!/bin/bash

printf 'grim %s\n' "$*" >>"$OMARCHY_TEST_CALLS"
: >"${@: -1}"
SH

cat >"$stub_bin/pkill" <<'SH'
#!/bin/bash
exit 1
SH

for stub in wl-copy omarchy-notification-send; do
  printf '#!/bin/bash\ncat >/dev/null 2>&1 || true\n' >"$stub_bin/$stub"
done

chmod +x "$stub_bin"/*
export PATH="$stub_bin:$ROOT/bin:$PATH"
export HOME="$tmp_dir"
export OMARCHY_SCREENSHOT_DIR="$tmp_dir/shots"

"$ROOT/bin/omarchy-capture-screenshot" region save >/dev/null

calls=$(<"$OMARCHY_TEST_CALLS")
force_line=$(grep -n 'no_hardware_cursors = 0' <<<"$calls" | head -1 | cut -d: -f1)
pick_line=$(grep -n '^pick ' <<<"$calls" | head -1 | cut -d: -f1)
grim_line=$(grep -n '^grim ' <<<"$calls" | head -1 | cut -d: -f1)
restore_line=$(grep -n 'no_hardware_cursors = 1' <<<"$calls" | head -1 | cut -d: -f1)

[[ -n $force_line && -n $pick_line && -n $grim_line && -n $restore_line ]] ||
  fail "the screenshot forces and restores hardware cursors around the capture" "$calls"

# Software cursors are the only pointer a machine with a broken hardware cursor
# plane has, so the picker has to run with the setting the user is on.
(( pick_line < force_line )) ||
  fail "hardware cursors are not forced until the region has been picked" "$calls"
pass "hardware cursors are not forced until the region has been picked"

(( force_line < grim_line )) ||
  fail "hardware cursors are forced before grim captures the frame" "$calls"
pass "hardware cursors are forced before grim captures the frame"

(( grim_line < restore_line )) ||
  fail "the previous cursor setting is restored after the capture" "$calls"
pass "the previous cursor setting is restored after the capture"

# A cancelled pick never changes the setting, so it has nothing to put back.
cat >"$stub_bin/omarchy-capture-region" <<'SH'
#!/bin/bash

printf '\n'
SH
chmod +x "$stub_bin/omarchy-capture-region"
: >"$OMARCHY_TEST_CALLS"

"$ROOT/bin/omarchy-capture-screenshot" region save >/dev/null

if grep -q 'no_hardware_cursors' "$OMARCHY_TEST_CALLS"; then
  fail "a cancelled pick leaves the cursor setting alone" "$(<"$OMARCHY_TEST_CALLS")"
fi
pass "a cancelled pick leaves the cursor setting alone"
