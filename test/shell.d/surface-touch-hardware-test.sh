#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/surface-touch.sh"
pacman_hardware="$ROOT/install/hardware/pacman.sh"
all_hardware="$ROOT/install/hardware/all.sh"
defaults_conf="$ROOT/etc/limine-entry-tool.d/omarchy-defaults.conf"

# The hardware leaf is wired into the install flow right after surface.sh.
grep -Fq 'run_logged "$OMARCHY_INSTALL/hardware/surface-touch.sh"' "$all_hardware" ||
  fail "surface-touch.sh runs from the hardware install flow"
grep -A1 'run_logged "$OMARCHY_INSTALL/hardware/surface.sh"' "$all_hardware" | grep -q 'surface-touch' ||
  fail "surface-touch.sh runs directly after surface.sh"
# The repository must be restored after the final pacman.conf restore.
grep -Fq 'linux-surface' "$pacman_hardware" ||
  fail "pacman.sh persists the linux-surface repository across the conf restore"
grep -Fq 'omarchy-pkg-add linux-surface linux-surface-headers iptsd' "$leaf" ||
  fail "the leaf installs kernel, headers, and iptsd together"
# Regression guard: the Secure Boot flag lives past the 4-byte attributes
# header of an efivarfs variable, and od needs an explicit type.
grep -Fq 'bs=1 skip=4 count=1 status=none | od -An -tu1' "$leaf" ||
  fail "Secure Boot reads the enabled byte at offset 4 of the efivarfs variable"
pass "surface-touch install flow wiring looks correct"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/omarchy-hw-surface" <<'SH'
#!/bin/bash

(( ${SURFACE_HARDWARE:-0} == 1 ))
SH

cat >"$stub_bin/pacman-key" <<'SH'
#!/bin/bash

# Simulate keyring state: the key shows up in --list-keys only after an
# --add has happened through this stub.
marker="$(dirname -- "$TEST_LOG")/surface-key-imported"

case "$1" in
--list-keys)
  # Exit status of the marker check is whether the key exists yet.
  [[ -f $marker ]]
  ;;
*)
  printf 'pacman-key' >>"$TEST_LOG"
  printf '\t%s' "$@" >>"$TEST_LOG"
  printf '\n' >>"$TEST_LOG"
  if [[ $1 == "--add" ]]; then
    touch "$marker"
  fi
  exit 0
  ;;
esac
SH

cat >"$stub_bin/curl" <<'SH'
#!/bin/bash

printf 'curl\tkey-import\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash

printf 'pacman' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash

printf 'omarchy-pkg-add' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash

(( ${SURFACE_KERNEL_INSTALLED:-0} == 1 ))
SH

chmod +x "$stub_bin"/*

pacman_conf="$test_tmp/pacman.conf"
efivars="$test_tmp/efivars"
entry_tool_dir="$test_tmp/limine-entry-tool.d"
mkdir -p "$efivars" "$entry_tool_dir"

cat >"$pacman_conf" <<'EOF'
[options]
HoldPkg = pacman glibc

[core]
Include = /etc/pacman.d/mirrorlist
EOF

run_leaf() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    SURFACE_HARDWARE=$1 \
    OMARCHY_PACMAN_CONF="$pacman_conf" \
    OMARCHY_EFIVARS_DIR="$efivars" \
    OMARCHY_LIMINE_ENTRY_TOOL_DIR="$entry_tool_dir" \
    bash -eE -c 'source "$1"' bash "$leaf" >/dev/null
}

secure_boot_var="$efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"

# Non-Surface hardware: nothing is configured or installed.
printf '\x06\x00\x00\x00\x00' >"$secure_boot_var"
: >"$calls"
run_leaf 0
[[ ! -s $calls ]] || fail "a non-Surface device is left alone" "$(cat "$calls")"
grep -q '^\[linux-surface\]' "$pacman_conf" &&
  fail "no repository is added on non-Surface hardware"
[[ ! -f $entry_tool_dir/zz-surface-touch.conf ]] ||
  fail "no boot order drop-in lands on non-Surface hardware"
pass "non-Surface devices are skipped entirely"

# Secure Boot enabled: the unsigned surface kernel would not boot.
printf '\x06\x00\x00\x00\x01' >"$secure_boot_var"
: >"$calls"
run_leaf 1
! grep -Fq 'omarchy-pkg-add' "$calls" ||
  fail "no packages are installed while Secure Boot blocks the kernel"
! grep -q '^\[linux-surface\]' "$pacman_conf" ||
  fail "no repository is added while Secure Boot blocks the kernel"
[[ ! -f $entry_tool_dir/zz-surface-touch.conf ]] ||
  fail "no boot order drop-in lands while Secure Boot blocks the kernel"
pass "enabled Secure Boot skips the surface kernel install"

# An unreadable or truncated efivar leaves the Secure Boot state unknown;
# installing an unbootable kernel would be worse than skipping it.
printf '\x06\x00' >"$secure_boot_var"
: >"$calls"
run_leaf 1
! grep -Fq 'omarchy-pkg-add' "$calls" ||
  fail "an undecidable Secure Boot state does not install the kernel"
[[ ! -f $entry_tool_dir/zz-surface-touch.conf ]] ||
  fail "an undecidable Secure Boot state creates no boot order drop-in"
pass "undecidable Secure Boot state fails closed"

# Surface with Secure Boot off: key trust, repository, packages, boot order.
printf '\x06\x00\x00\x00\x00' >"$secure_boot_var"
: >"$calls"
run_leaf 1
grep -Fq $'curl\tkey-import' "$calls" ||
  fail "imports the linux-surface signing key before installing"
grep -Fq $'pacman-key\t--lsign-key\t56C464BAAC421453' "$calls" ||
  fail "locally signs the linux-surface signing key"
grep -q '^\[linux-surface\]' "$pacman_conf" ||
  fail "adds the linux-surface repository"
grep -A1 '^\[linux-surface\]' "$pacman_conf" | grep -Fq 'Server = https://pkg.surfacelinux.com/arch/' ||
  fail "points the linux-surface repository at pkg.surfacelinux.com"
grep -Fq $'pacman\t-Syu\t--noconfirm' "$calls" ||
  fail "full-syncs after adding the repository instead of a partial refresh"
grep -Fq $'omarchy-pkg-add\tlinux-surface\tlinux-surface-headers\tiptsd' "$calls" ||
  fail "installs the surface kernel, headers, and iptsd"
grep -Fq 'BOOT_ORDER="linux, linux-surface*, *fallback, Snapshots"' "$entry_tool_dir/zz-surface-touch.conf" ||
  fail "boot order keeps the stock kernel first and the surface kernel available"
pass "Surface setup trusts the key, adds the repo, installs, and orders boot entries"

# Rerunning stays idempotent: no duplicated config sections, drop-ins, or
# redundant key imports.
before_dropin=$(cat "$entry_tool_dir/zz-surface-touch.conf")
run_leaf 1
(( $(grep -c '^\[linux-surface\]' "$pacman_conf") == 1 )) ||
  fail "reruns do not duplicate the linux-surface repository entry"
[[ $(cat "$entry_tool_dir/zz-surface-touch.conf") == "$before_dropin" ]] ||
  fail "reruns leave the boot order drop-in unchanged"
(( $(grep -c 'curl' "$calls") == 1 )) ||
  fail "an imported signing key is not re-downloaded on reruns"
pass "reruns are idempotent"

# The persisted repository survives a post-install pacman.conf restore: start
# from a pristine configuration without the entry, as the final restore
# produces, then verify restoration and idempotence against it.
cat >"$pacman_conf" <<'EOF'
[options]
HoldPkg = pacman glibc

[core]
Include = /etc/pacman.d/mirrorlist
EOF

run_pacman_hardware() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    SURFACE_HARDWARE=$1 \
    SURFACE_KERNEL_INSTALLED=$2 \
    OMARCHY_PACMAN_CONF="$pacman_conf" \
    bash -eE -c 'source "$1"' bash "$pacman_hardware" >/dev/null
}

# A Secure Boot skip never installed the kernel, so its repository must not
# appear either.
: >"$calls"
run_pacman_hardware 1 0
! grep -q '^\[linux-surface\]' "$pacman_conf" ||
  fail "no repository is restored when the surface kernel is not installed"
pass "Secure Boot skips keep the third-party repository away"

run_pacman_hardware 1 1
grep -q '^\[linux-surface\]' "$pacman_conf" ||
  fail "pacman.sh re-adds the linux-surface repository after a conf restore"
(( $(grep -c '^\[linux-surface\]' "$pacman_conf") == 1 )) ||
  fail "pacman.sh does not duplicate the linux-surface repository entry"

run_pacman_hardware 1 1
(( $(grep -c '^\[linux-surface\]' "$pacman_conf") == 1 )) ||
  fail "pacman.sh stays idempotent across reruns"
pass "the linux-surface repository survives the final pacman.conf restore"
