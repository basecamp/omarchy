#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
proc_root="$test_tmp/proc"
mutation_log="$test_tmp/mutations.log"
mkdir -p "$stub_bin" "$proc_root/device-tree" "$test_tmp/home"

cat >"$stub_bin/uname" <<'EOF'
#!/bin/bash
printf '%s\n' "${OMARCHY_TEST_ARCH:-aarch64}"
EOF
chmod +x "$stub_bin/uname"

printf 'apple,j314s\0apple,arm-platform\0' >"$proc_root/device-tree/compatible"
OMARCHY_PROC_ROOT="$proc_root" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-hw-apple-silicon" ||
  fail "Apple Silicon detector accepts aarch64 Apple device trees"
pass "Apple Silicon detector accepts aarch64 Apple device trees"

if OMARCHY_TEST_ARCH=x86_64 OMARCHY_PROC_ROOT="$proc_root" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-hw-apple-silicon"; then
  fail "Apple Silicon detector rejects non-aarch64 systems"
fi
pass "Apple Silicon detector rejects non-aarch64 systems"

printf 'linux,dummy-virt\0' >"$proc_root/device-tree/compatible"
if OMARCHY_PROC_ROOT="$proc_root" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-hw-apple-silicon"; then
  fail "Apple Silicon detector rejects non-Apple aarch64 systems"
fi
pass "Apple Silicon detector rejects non-Apple aarch64 systems"

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$stub_bin/omarchy-hw-apple-silicon"

# Every command the guarded scripts would reach past the gate logs instead of
# acting, so a guard that fires late shows up as a logged mutation.
for command_name in sudo pacman gum git omarchy-refresh-pacman omarchy-dev-link omarchy-dev-unlink omarchy-state omarchy-update efibootmgr; do
  cat >"$stub_bin/$command_name" <<'EOF'
#!/bin/bash
printf '%s\n' "$(basename "$0") $*" >>"$OMARCHY_TEST_MUTATION_LOG"
EOF
  chmod +x "$stub_bin/$command_name"
done

run_guarded() {
  local command_path="$1"
  shift

  : >"$mutation_log"
  if OMARCHY_TEST_MUTATION_LOG="$mutation_log" OMARCHY_PATH="$ROOT" HOME="$test_tmp/home" PATH="$stub_bin:/usr/bin:/bin" \
    "$command_path" "$@" >"$test_tmp/output" 2>"$test_tmp/error"; then
    fail "$(basename "$command_path") rejects Apple Silicon"
  fi
  [[ ! -s $mutation_log ]] || fail "$(basename "$command_path") stops before mutation" "$(cat "$mutation_log")"
}

run_guarded "$ROOT/bin/omarchy-refresh-pacman" stable
grep -F "no per-channel aarch64 repository for Apple Silicon" "$test_tmp/error" >/dev/null ||
  fail "pacman refresh explains the Apple Silicon repository guard"
pass "pacman refresh rejects Apple Silicon before mutation"

run_guarded "$ROOT/bin/omarchy-channel-set" dev
grep -F "no per-channel aarch64 repository for Apple Silicon" "$test_tmp/error" >/dev/null ||
  fail "channel setup explains the missing Apple Silicon package repository"
pass "channel setup rejects Apple Silicon before checkout or package mutation"

run_guarded "$ROOT/bin/omarchy-setup-direct-boot"
grep -F "Direct boot is not supported on Apple Silicon" "$test_tmp/error" >/dev/null ||
  fail "direct boot explains the Apple Silicon restriction"
pass "direct boot rejects Apple Silicon before EFI inspection or mutation"

: >"$mutation_log"
cat >"$stub_bin/lspci" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$stub_bin/omarchy-pkg-add" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_MUTATION_LOG"
EOF
chmod +x "$stub_bin/lspci" "$stub_bin/omarchy-pkg-add"

OMARCHY_TEST_MUTATION_LOG="$mutation_log" PATH="$stub_bin:/usr/bin:/bin" bash "$ROOT/install/hardware/vulkan.sh"
[[ $(cat "$mutation_log") == "vulkan-asahi" ]] || fail "Vulkan setup selects vulkan-asahi from the Apple Silicon detector" "$(cat "$mutation_log")"
pass "Vulkan setup selects vulkan-asahi from the Apple Silicon detector"
