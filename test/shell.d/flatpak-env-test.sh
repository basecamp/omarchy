#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

uwsm_env="$ROOT/default/uwsm/env.d/10-omarchy"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# A stub in the shape of /etc/profile.d/flatpak.sh: prepend Flatpak's export
# dirs to XDG_DATA_DIRS, but only when flatpak is on PATH.
stub="$test_tmp/flatpak.sh"
cat > "$stub" <<'EOF'
if command -v flatpak > /dev/null; then
  export XDG_DATA_DIRS="/home/test/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:$XDG_DATA_DIRS"
fi
EOF
mkdir -p "$test_tmp/bin"
printf '#!/bin/sh\nexit 0\n' > "$test_tmp/bin/flatpak"
chmod +x "$test_tmp/bin/flatpak"

run_uwsm_env() {
  local flatpak_profile="$1"
  local bin_dir="$2"

  HOME=/home/test OMARCHY_PATH="$ROOT" XDG_DATA_HOME=/home/test/.local/share \
    XDG_DATA_DIRS="/some/base" OMARCHY_FLATPAK_PROFILE="$flatpak_profile" \
    bash -c 'PATH="$2:$ROOT/bin"; source "$1"; printf "%s" "$XDG_DATA_DIRS"' bash \
    "$uwsm_env" "$bin_dir"
}

# With Flatpak installed, the session env picks up its export dirs ahead of the
# inherited XDG_DATA_DIRS.
xdg=$(run_uwsm_env "$stub" "$test_tmp/bin")
[[ $xdg == "/home/test/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/some/base" ]] ||
  fail "session env adds Flatpak export dirs when Flatpak is installed" "actual: $xdg"
pass "session env adds Flatpak export dirs when Flatpak is installed"

# The Flatpak script is only sourced when present.
xdg=$(run_uwsm_env "$test_tmp/missing.sh" "$test_tmp/bin")
[[ $xdg == "/some/base" ]] ||
  fail "session env leaves XDG_DATA_DIRS alone without the Flatpak script" "actual: $xdg"
pass "session env leaves XDG_DATA_DIRS alone without the Flatpak script"

# flatpak.sh skips itself (and the env is unchanged) when Flatpak is absent.
xdg=$(run_uwsm_env "$stub" "$test_tmp/empty")
[[ $xdg == "/some/base" ]] ||
  fail "session env leaves XDG_DATA_DIRS alone when Flatpak is not installed" "actual: $xdg"
pass "session env leaves XDG_DATA_DIRS alone when Flatpak is not installed"