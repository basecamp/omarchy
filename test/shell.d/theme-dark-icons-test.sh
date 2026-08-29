#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

bad=()
for colors in "$ROOT"/themes/*/colors.toml; do
  mode=$(head -1 "$colors")
  [[ $mode == *dark* ]] || continue
  icons="$(dirname "$colors")/icons.theme"
  [[ -f $icons ]] || continue
  value=$(tr -d '[:space:]' <"$icons")
  [[ $value == *-dark ]] || bad+=("$(basename "$(dirname "$colors")"):$value")
done

(( ${#bad[@]} == 0 )) || fail "dark themes must use Yaru-*-dark icons: ${bad[*]}"
pass "dark themes ship Yaru-*-dark icon variants"
