#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"

cat >"$TEST_ROOT/bin/hyprctl" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$HYPRCTL_CALLS"

case "$1 $2" in
  "clients -j")
    printf '%s\n' '[
      {"address":"0x1","workspace":{"id":1}},
      {"address":"0x2","workspace":{"id":3}},
      {"address":"0x3","workspace":{"id":3}},
      {"address":"0x4","workspace":{"id":7}},
      {"address":"0x5","workspace":{"id":-99}}
    ]'
    ;;
  "activeworkspace -j")
    printf '%s\n' '{"id":7}'
    ;;
  "--batch "*) ;;
  *) exit 1 ;;
esac
SH
chmod +x "$TEST_ROOT/bin/hyprctl"

export HYPRCTL_CALLS="$TEST_ROOT/hyprctl-calls"
PATH="$TEST_ROOT/bin:$PATH" "$ROOT/bin/omarchy-hyprland-workspace-compact"

mapfile -t calls <"$HYPRCTL_CALLS"
[[ ${#calls[@]} == 3 ]] || fail "workspace compaction uses three hyprctl calls" "${calls[*]}"
[[ ${calls[0]} == "clients -j" ]] || fail "workspace compaction reads clients once" "${calls[0]}"
[[ ${calls[1]} == "activeworkspace -j" ]] || fail "workspace compaction reads the active workspace once" "${calls[1]}"

batch=${calls[2]}
[[ $batch == "--batch "* ]] || fail "workspace compaction sends one dispatch batch" "$batch"
[[ $batch == *'address:0x2'* ]] || fail "workspace compaction moves the first window from a gapped workspace"
[[ $batch == *'address:0x3'* ]] || fail "workspace compaction moves every window from a gapped workspace"
[[ $batch == *'address:0x4'* ]] || fail "workspace compaction moves later occupied workspaces"
[[ $batch != *'address:0x1'* ]] || fail "workspace compaction leaves already compact windows alone"
[[ $batch != *'address:0x5'* ]] || fail "workspace compaction leaves special workspaces alone"
[[ $batch == *'workspace = "3"'*'hl.dsp.focus'* ]] || fail "workspace compaction follows the renumbered active workspace" "$batch"

pass "workspace compaction batches window moves and preserves workspace behavior"
