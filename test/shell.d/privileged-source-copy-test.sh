#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

helpers=(
  "$ROOT/bin/omarchy-refresh-limine"
  "$ROOT/bin/omarchy-refresh-pacman"
  "$ROOT/bin/omarchy-toggle-hybrid-gpu"
  "$ROOT/bin/omarchy-hibernation-setup"
)

for helper in "${helpers[@]}"; do
  grep -F 'omarchy_privileged_source_root()' "$helper" >/dev/null ||
    fail "$(basename "$helper") resolves privileged copies through a trusted source root"
  if grep -E 'sudo cp.*\$OMARCHY_PATH/' "$helper" >/dev/null; then
    fail "$(basename "$helper") no longer sudo-copies from a caller-controlled OMARCHY_PATH"
  fi
done

grep -F 'sudo cp "$SOURCE_ROOT/default/limine/limine.conf" /boot/limine.conf' \
  "$ROOT/bin/omarchy-refresh-limine" >/dev/null ||
  fail "omarchy-refresh-limine copies limine.conf from the trusted source root"

grep -F 'sudo cp -f "$SOURCE_ROOT/default/pacman/pacman-$channel.conf" /etc/pacman.conf' \
  "$ROOT/bin/omarchy-refresh-pacman" >/dev/null ||
  fail "omarchy-refresh-pacman copies pacman.conf from the trusted source root"

grep -F 'sudo cp -p "$SOURCE_ROOT/default/systemd/system-sleep/force-igpu"' \
  "$ROOT/bin/omarchy-toggle-hybrid-gpu" >/dev/null ||
  fail "omarchy-toggle-hybrid-gpu copies force-igpu from the trusted source root"

grep -F 'sudo cp -p "$SOURCE_ROOT/default/systemd/system-sleep/keyboard-backlight"' \
  "$ROOT/bin/omarchy-hibernation-setup" >/dev/null ||
  fail "omarchy-hibernation-setup copies keyboard-backlight from the trusted source root"

pass "privileged copies read the packaged tree, not a caller-controlled OMARCHY_PATH"

if (( EUID == 0 )); then
  pass "running as root; skipping the elevation checks, which would rewrite boot and pacman files"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
evil="$test_tmp/evil-tree"
mkdir -p "$stub_bin" \
  "$evil/default/limine" \
  "$evil/default/pacman"

printf 'not the packaged limine\n' >"$evil/default/limine/limine.conf"
printf 'not the packaged pacman\n' >"$evil/default/pacman/pacman-stable.conf"
printf 'not the packaged mirrorlist\n' >"$evil/default/pacman/mirrorlist-stable"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$ELEVATION_LOG"
SH
chmod +x "$stub_bin/sudo"

cat >"$stub_bin/omarchy-hook" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin/omarchy-hook"

elevation_log="$test_tmp/elevation"
: >"$elevation_log"

HOME="$test_tmp" OMARCHY_PATH="$evil" ELEVATION_LOG="$elevation_log" \
  PATH="$stub_bin:/usr/bin" \
  "$ROOT/bin/omarchy-refresh-limine" >/dev/null 2>&1 || true

if grep -F "$evil" "$elevation_log"; then
  fail "omarchy-refresh-limine does not sudo-copy from a poisoned OMARCHY_PATH" \
    "$(cat "$elevation_log")"
fi
grep -F "sudo cp /usr/share/omarchy/default/limine/limine.conf /boot/limine.conf" "$elevation_log" >/dev/null ||
  fail "omarchy-refresh-limine sudo-copies the packaged limine.conf" \
    "$(cat "$elevation_log")"

pass "omarchy-refresh-limine ignores a poisoned OMARCHY_PATH"

: >"$elevation_log"
HOME="$test_tmp" OMARCHY_PATH="$evil" ELEVATION_LOG="$elevation_log" \
  PATH="$stub_bin:/usr/bin" \
  "$ROOT/bin/omarchy-refresh-pacman" stable >/dev/null 2>&1 || true

if grep -F "$evil" "$elevation_log"; then
  fail "omarchy-refresh-pacman does not sudo-copy from a poisoned OMARCHY_PATH" \
    "$(cat "$elevation_log")"
fi
grep -F "sudo cp -f /usr/share/omarchy/default/pacman/pacman-stable.conf /etc/pacman.conf" "$elevation_log" >/dev/null ||
  fail "omarchy-refresh-pacman sudo-copies the packaged pacman.conf" \
    "$(cat "$elevation_log")"

pass "omarchy-refresh-pacman ignores a poisoned OMARCHY_PATH"
