#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
gum_marker="$test_tmp/gum"
reboot_marker="$test_tmp/reboot"
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

write_stub uname 'echo test-kernel'
write_stub pacman 'exit 1'
write_stub pgrep 'exit 1'
write_stub readlink 'exit 1'
write_stub gum 'touch "$GUM_MARKER"; exit 99'
write_stub omarchy-system-reboot 'touch "$REBOOT_MARKER"'
write_stub omarchy-restart-shell 'exit 0'

output=$(
  HOME="$test_home" \
    PATH="$stub_bin:$PATH" \
    GUM_MARKER="$gum_marker" \
    REBOOT_MARKER="$reboot_marker" \
    OMARCHY_UPDATE_UNATTENDED=1 \
    "$ROOT/bin/omarchy-update-restart"
)

[[ $output == *"Linux kernel has been updated. Reboot? Reboot when convenient."* ]] ||
  fail "unattended restart check reports a required reboot"
[[ ! -f $gum_marker ]] || fail "unattended restart check does not prompt"
[[ ! -f $reboot_marker ]] || fail "unattended restart check does not reboot"
[[ $output == *"Restarting shell"* ]] || fail "unattended restart check still completes service restarts"
pass "unattended restart checks report without prompting"
