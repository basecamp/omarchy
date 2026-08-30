#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
offline_config="$test_tmp/pacman.conf"
online_config="$test_tmp/omarchy/default/pacman/pacman-stable.conf"
pacman_calls="$test_tmp/pacman-calls"

mkdir -p "$mock_bin" "$(dirname "$online_config")"
touch "$online_config"
cat > "$offline_config" <<'EOF'
[offline]
Server = file:///var/cache/omarchy/mirror/offline/
EOF

cat > "$mock_bin/omarchy-pkg-missing" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$mock_bin/pacman" <<'EOF'
#!/bin/bash

printf '%q ' "$@" >> "$OMARCHY_TEST_PACMAN_CALLS"
printf '\n' >> "$OMARCHY_TEST_PACMAN_CALLS"

if [[ ${1:-} == -Q ]]; then
  exit 0
fi

if [[ ${1:-} == --config ]]; then
  [[ ${OMARCHY_UPDATE_PACMAN:-} == 1 ]]
  exit
fi

exit 1
EOF

cat > "$mock_bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF

chmod +x "$mock_bin/omarchy-pkg-missing" "$mock_bin/pacman" "$mock_bin/sudo"

PATH="$mock_bin:$ROOT/bin:$PATH" \
OMARCHY_MIRROR=stable \
OMARCHY_PACMAN_CONFIG="$offline_config" \
OMARCHY_PATH="$test_tmp/omarchy" \
OMARCHY_TEST_PACMAN_CALLS="$pacman_calls" \
  "$ROOT/bin/omarchy-pkg-add" example-package

(( $(wc -l < "$pacman_calls") == 3 )) ||
  fail "an offline package failure retries once with the online configuration"
grep -F -- '-S --noconfirm --needed example-package' "$pacman_calls" >/dev/null ||
  fail "the first package attempt still uses the active offline configuration"
grep -F -- "--config $online_config -Syyu --noconfirm --needed example-package" "$pacman_calls" >/dev/null ||
  fail "the retry uses the selected online pacman configuration"
pass "an offline package failure retries once with the online configuration"

cat > "$offline_config" <<'EOF'
[core]
Server = https://mirror.example.invalid/core/os/x86_64
EOF
: > "$pacman_calls"

if PATH="$mock_bin:$ROOT/bin:$PATH" \
  OMARCHY_MIRROR=stable \
  OMARCHY_PACMAN_CONFIG="$offline_config" \
  OMARCHY_PATH="$test_tmp/omarchy" \
  OMARCHY_TEST_PACMAN_CALLS="$pacman_calls" \
    "$ROOT/bin/omarchy-pkg-add" example-package; then
  echo "Expected package installation to fail without the offline config" >&2
  exit 1
fi

! grep -F -- '--config' "$pacman_calls" >/dev/null ||
  fail "a normal package failure unexpectedly switched to online repositories"
pass "a normal package failure does not switch to online repositories"
