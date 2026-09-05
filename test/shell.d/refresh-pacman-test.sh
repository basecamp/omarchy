#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# The command writes to /etc/pacman.conf and /etc/pacman.d/mirrorlist, so a
# full copy with the absolute paths rewritten into the sandbox is used. The
# hardware repo script is copied the same way.
sandbox_conf="$tmp_dir/etc/pacman.conf"
sandbox_mirror="$tmp_dir/etc/pacman.d/mirrorlist"
mkdir -p "$tmp_dir/etc/pacman.d" "$tmp_dir/omarchy/default/pacman" \
  "$tmp_dir/omarchy/install/hardware" "$tmp_dir/bin"

printf '#%%current\n[core]\nServer = https://example.org/core\n' >"$sandbox_conf"
printf 'Server = https://example.org/mirror\n' >"$sandbox_mirror"
printf '#%%generated\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' \
  >"$tmp_dir/omarchy/default/pacman/pacman-stable.conf"
printf 'Server = https://example.org/mirror\n' \
  >"$tmp_dir/omarchy/default/pacman/mirrorlist-stable"

# Sandboxed copy of install/hardware/pacman.sh with /etc/pacman.conf rewritten.
sed -e "s|/etc/pacman.conf|$sandbox_conf|g" \
  "$ROOT/install/hardware/pacman.sh" >"$tmp_dir/omarchy/install/hardware/pacman.sh"

# Sandboxed copy of the command itself.
sed -e "s|/etc/pacman.conf|$sandbox_conf|g" \
  -e "s|/etc/pacman.d/mirrorlist|$sandbox_mirror|g" \
  "$ROOT/bin/omarchy-refresh-pacman" >"$tmp_dir/leaf.sh"

cat >"$tmp_dir/bin/lspci" <<'EOF'
#!/bin/bash
printf '%s\n' "$LSPCI_OUT"
EOF

cat >"$tmp_dir/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$SUDO_LOG"
exec "$@"
EOF

cat >"$tmp_dir/bin/pacman" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PACMAN_LOG"
EOF

cat >"$tmp_dir/bin/omarchy-hook" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HOOK_LOG"
EOF

chmod +x "$tmp_dir/bin"/*

run_refresh() {
  LSPCI_OUT="$1" \
    SUDO_LOG="$tmp_dir/sudo.log" \
    PACMAN_LOG="$tmp_dir/pacman.log" \
    HOOK_LOG="$tmp_dir/hook.log" \
    OMARCHY_PATH="$tmp_dir/omarchy" \
    PATH="$tmp_dir/bin:$PATH" \
    bash "$tmp_dir/leaf.sh"
}

# On Apple T2 hardware (lspci shows 106b:1801) the [arch-mact2] repository must
# survive the template restore, otherwise linux-t2 loses its update source.
run_refresh "0000:00:1c.4 PCI bridge: Apple Inc. 106b:1801"
grep -q '^\[arch-mact2\]' "$sandbox_conf" ||
  fail "the arch-mact2 repository survives a refresh on T2 hardware" \
    "$(cat "$sandbox_conf")"
grep -q 'NoaHimesaka1873/arch-mact2-mirror' "$sandbox_conf" ||
  fail "the arch-mact2 mirror server is re-appended" "$(cat "$sandbox_conf")"
grep -q 'pre-refresh-pacman' "$tmp_dir/hook.log" ||
  fail "the pre-refresh-pacman hook still runs"
grep -q -- '-Syyuu' "$tmp_dir/pacman.log" ||
  fail "pacman -Syyuu still runs after the restore" "$(cat "$tmp_dir/pacman.log")"
pass "T2 hardware keeps its arch-mact2 repo through a refresh"

# Idempotent: a second refresh must not duplicate the stanza.
run_refresh "0000:00:1c.4 PCI bridge: Apple Inc. 106b:1801"
(( $(grep -c '^\[arch-mact2\]' "$sandbox_conf") == 1 )) ||
  fail "the arch-mact2 repo is appended only once" "$(cat "$sandbox_conf")"
pass "a second refresh does not duplicate the arch-mact2 stanza"

# Non-T2 hardware: nothing added, nothing broken.
printf '#%%current\n[core]\nServer = https://example.org/core\n' >"$sandbox_conf"
run_refresh "0000:01:00.0 VGA compatible controller: NVIDIA Corporation"
grep -q '^\[arch-mact2\]' "$sandbox_conf" &&
  fail "non-T2 hardware gets no arch-mact2 stanza" "$(cat "$sandbox_conf")"
pass "non-T2 hardware is untouched"

# If the hardware re-apply itself fails (say a future pacman.sh cannot fetch
# a signing key), the refresh must stop before the upgrade: continuing and
# running pacman -Syyuu with the repo missing is the same silent failure
# #9853 reports. The command has no set -e, so this only holds if the
# re-apply step is checked explicitly.
mkdir -p "$tmp_dir/omarchy-broken/install/hardware" \
  "$tmp_dir/omarchy-broken/default/pacman"
printf '#%%generated\n' >"$tmp_dir/omarchy-broken/default/pacman/pacman-stable.conf"
printf 'Server = https://example.org/mirror\n' \
  >"$tmp_dir/omarchy-broken/default/pacman/mirrorlist-stable"
printf 'echo "key import failed" >&2\nexit 1\n' \
  >"$tmp_dir/omarchy-broken/install/hardware/pacman.sh"
chmod +x "$tmp_dir/omarchy-broken/install/hardware/pacman.sh"
rm -f "$tmp_dir/pacman.log" "$tmp_dir/hook.log"
if LSPCI_OUT="" PACMAN_LOG="$tmp_dir/pacman.log" HOOK_LOG="$tmp_dir/hook.log" \
  SUDO_LOG="$tmp_dir/sudo.log" OMARCHY_PATH="$tmp_dir/omarchy-broken" \
  PATH="$tmp_dir/bin:$PATH" \
  bash "$tmp_dir/leaf.sh" >"$tmp_dir/broken.out" 2>&1; then
  fail "a failed hardware re-apply aborts the refresh" \
    "$(cat "$tmp_dir/broken.out")"
fi
[[ ! -s $tmp_dir/pacman.log ]] ||
  fail "the upgrade does not run after a failed re-apply" \
    "$(cat "$tmp_dir/pacman.log")"
grep -q "Failed to re-apply hardware pacman repos" "$tmp_dir/broken.out" ||
  fail "the failure is reported before aborting" "$(cat "$tmp_dir/broken.out")"
pass "a failed hardware re-apply aborts before the upgrade"

pass "refresh pacman re-applies hardware repos and upgrades cleanly"
