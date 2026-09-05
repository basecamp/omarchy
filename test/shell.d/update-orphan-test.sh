#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command script

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$stub_bin" "$test_home"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

run_orphan_checker() {
  HOME="$test_home" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-update-orphan-pkgs"
}

run_unattended_orphan_checker_on_terminal() {
  HOME="$test_home" PATH="$stub_bin:$PATH" OMARCHY_UPDATE_UNATTENDED=1 \
    script -qec "bash '$ROOT/bin/omarchy-update-orphan-pkgs'" "$test_tmp/unattended.out" >/dev/null 2>&1
}

write_stub pacman 'if [[ $1 == "-Qtdq" ]]; then printf "old-lib\nunused-tool\n"; exit 0; fi; exit 1'
write_stub sudo 'echo "sudo should not be called" >&2; exit 99'
write_stub gum 'echo "gum should not be called" >&2; exit 99'

run_orphan_checker >"$test_tmp/noninteractive.out" 2>"$test_tmp/noninteractive.err"
grep -q '^  old-lib$' "$test_tmp/noninteractive.out" || fail "orphan checker lists orphan packages"
grep -q 'Re-run omarchy-update-orphan-pkgs in a terminal' "$test_tmp/noninteractive.out" || fail "orphan checker does not remove packages non-interactively"
pass "orphan checker only reports orphans non-interactively"

run_unattended_orphan_checker_on_terminal || fail "unattended orphan checker fails on a terminal"
grep -q 'Re-run omarchy-update-orphan-pkgs in a terminal' "$test_tmp/unattended.out" ||
  fail "unattended orphan checker prompts inside the update pseudo-terminal"
if grep -q 'should not be called' "$test_tmp/unattended.out"; then
  fail "unattended orphan checker calls an interactive or privileged command"
fi
pass "unattended orphan checker only reports orphans on a terminal"

write_stub pacman 'if [[ $1 == "-Qtdq" ]]; then exit 0; fi; exit 1'
run_orphan_checker >"$test_tmp/none.out" 2>"$test_tmp/none.err"
[[ ! -s $test_tmp/none.out ]] || fail "orphan checker stays quiet when no orphans exist"
pass "orphan checker stays quiet without orphans"
