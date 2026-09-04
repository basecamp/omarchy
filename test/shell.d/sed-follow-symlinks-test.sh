#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

# sed -i without --follow-symlinks replaces symlinks with regular files,
# breaking dotfile setups that symlink configs from a version-controlled
# repository. Always use sed -i --follow-symlinks — it is critical for
# user files and harmless everywhere else.
#
# Allowlisted files operate on temporary/staging directories where
# symlink preservation is irrelevant.

ALLOWLIST=(
  bin/omarchy-dev-pkg-test
  bin/omarchy-plymouth-set
  bin/omarchy-upgrade-to-quattro
)

violations=()

is_allowlisted() {
  local rel="${1#$ROOT/}"
  local entry
  for entry in "${ALLOWLIST[@]}"; do
    [[ $rel == "$entry" ]] && return 0
  done
  return 1
}

while IFS=: read -r file lineno line; do
  local_line="${line#"${line%%[![:space:]]*}"}"
  [[ $local_line == \#* ]] && continue
  is_allowlisted "$file" && continue
  violations+=("${file#$ROOT/}:$lineno")
done < <(grep -rEn 'sed[[:space:]]+-i([[:space:]]|$)' "$ROOT/bin" "$ROOT/migrations" | grep -v -- '--follow-symlinks' || true)

if (( ${#violations[@]} > 0 )); then
  printf 'Found sed -i without --follow-symlinks on user-space files:\n' >&2
  printf '  %s\n' "${violations[@]}" >&2
  fail "all sed -i calls on user files use --follow-symlinks"
fi

pass "all sed -i calls on user files use --follow-symlinks"
