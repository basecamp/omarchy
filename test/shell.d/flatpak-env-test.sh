#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

uwsm_env="$ROOT/default/uwsm/env.d/10-omarchy"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Stands in for /etc/profile.d/flatpak.sh: prepend the export dirs of every
# installation, skip dirs already on XDG_DATA_DIRS, and do nothing at all when
# Flatpak is not on PATH. Same contract as the real hook, without needing
# Flatpak installed on the machine running the tests.
cat >"$tmp/flatpak.sh" <<'PROFILE'
if command -v flatpak >/dev/null; then
  for share_path in "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share" /var/lib/flatpak/exports/share; do
    case ":$XDG_DATA_DIRS:" in
    *":$share_path:"*) ;;
    *) XDG_DATA_DIRS="$share_path:$XDG_DATA_DIRS" ;;
    esac
  done
  export XDG_DATA_DIRS
fi
PROFILE

mkdir -p "$tmp/bin" "$tmp/empty"
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/flatpak"
chmod +x "$tmp/bin/flatpak"

session_data_dirs() {
  local profile="$1" path_dir="$2"

  HOME=/home/test \
    OMARCHY_PATH="$ROOT" \
    XDG_DATA_HOME=/home/test/.local/share \
    XDG_DATA_DIRS=/usr/local/share:/usr/share \
    OMARCHY_FLATPAK_PROFILE="$profile" \
    bash -c 'PATH="$2:$ROOT/bin"; source "$1"; printf "%s" "$XDG_DATA_DIRS"' bash "$uwsm_env" "$path_dir"
}

expected="/var/lib/flatpak/exports/share:/home/test/.local/share/flatpak/exports/share:/usr/local/share:/usr/share"

# The whole point: the session the launcher runs in can see Flatpak's exports.
actual=$(session_data_dirs "$tmp/flatpak.sh" "$tmp/bin")
[[ $actual == "$expected" ]] ||
  fail "session env picks up the Flatpak export dirs" "actual: $actual"
pass "session env picks up the Flatpak export dirs"

# Sourcing twice must not stack duplicates onto XDG_DATA_DIRS.
actual=$(HOME=/home/test OMARCHY_PATH="$ROOT" XDG_DATA_HOME=/home/test/.local/share \
  XDG_DATA_DIRS=/usr/local/share:/usr/share OMARCHY_FLATPAK_PROFILE="$tmp/flatpak.sh" \
  bash -c 'PATH="$2:$ROOT/bin"; source "$1"; source "$1"; printf "%s" "$XDG_DATA_DIRS"' bash "$uwsm_env" "$tmp/bin")
[[ $actual == "$expected" ]] ||
  fail "session env stays idempotent across reloads" "actual: $actual"
pass "session env stays idempotent across reloads"

# A machine without Flatpak keeps the stock search path.
actual=$(session_data_dirs "$tmp/flatpak.sh" "$tmp/empty")
[[ $actual == "/usr/local/share:/usr/share" ]] ||
  fail "session env is unchanged when Flatpak is not installed" "actual: $actual"
pass "session env is unchanged when Flatpak is not installed"

# And one without the hook file at all does not fail the session env.
actual=$(session_data_dirs "$tmp/absent.sh" "$tmp/bin")
[[ $actual == "/usr/local/share:/usr/share" ]] ||
  fail "session env is unchanged when the Flatpak hook is absent" "actual: $actual"
pass "session env is unchanged when the Flatpak hook is absent"
