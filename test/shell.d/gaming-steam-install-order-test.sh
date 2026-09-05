#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

script="$ROOT/bin/omarchy-install-gaming-steam"
[[ -x $script ]] || fail "omarchy-install-gaming-steam must be executable"

gpu_line=$(grep -n 'omarchy-install-gaming-gpu-lib32' "$script" | head -1 | cut -d: -f1)
steam_line=$(grep -n 'omarchy-pkg-add steam' "$script" | head -1 | cut -d: -f1)

[[ -n $gpu_line && -n $steam_line ]] || fail "steam installer must call both gpu-lib32 and pkg-add steam"
(( gpu_line < steam_line )) || fail "gpu-lib32 must run before steam so --noconfirm cannot pick lib32-nvidia-utils"

pass "steam installer resolves vulkan drivers before installing steam"
