#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# xpadneo is a DKMS module, so it builds against the headers of the kernel
# actually running: linux-headers on stock Arch, linux-asahi-headers on Apple
# Silicon, where linux-headers would not match the Asahi kernel.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
calls="$test_tmp/calls"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

cat >"$stub_bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash
printf 'omarchy-pkg-add %s\n' "$*" >>"$CALLS"
STUB

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'STUB'
#!/bin/bash
[[ ${APPLE_SILICON:-0} == 1 ]]
STUB

# The rest of the script writes under /etc and pokes the kernel; keep every
# such side effect inside the stubs. The user is already in the input group
# and xpad is not loaded, so no reboot prompt is reached.
cat >"$stub_bin/tee" <<'STUB'
#!/bin/bash
cat >/dev/null
STUB

cat >"$stub_bin/id" <<'STUB'
#!/bin/bash
echo "wheel input"
STUB

for tool in lsmod modprobe usermod gum reboot; do
  cat >"$stub_bin/$tool" <<STUB
#!/bin/bash
printf '$tool %s\\n' "\$*" >>"\$CALLS"
STUB
done

chmod +x "$stub_bin"/*

run_install() {
  : >"$calls"
  CALLS="$calls" \
    APPLE_SILICON="${APPLE_SILICON:-0}" \
    USER="${USER:-tester}" \
    PATH="$stub_bin:$PATH" \
    bash "$ROOT/bin/omarchy-install-gaming-xbox-controllers"
}

run_install >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "installing Xbox controller support fails" "$(<"$test_tmp/err")"
grep -qx 'omarchy-pkg-add linux-headers xpadneo-dkms' "$calls" ||
  fail "stock Arch does not build xpadneo against linux-headers" "$(<"$calls")"
pass "xpadneo builds against linux-headers on stock Arch"

APPLE_SILICON=1 run_install >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "installing Xbox controller support on Apple Silicon fails" "$(<"$test_tmp/err")"
grep -qx 'omarchy-pkg-add linux-asahi-headers xpadneo-dkms' "$calls" ||
  fail "Apple Silicon does not build xpadneo against linux-asahi-headers" "$(<"$calls")"
grep -q 'linux-headers' "$calls" &&
  fail "Apple Silicon installs linux-headers for a kernel it does not run"
grep -q 'reboot' "$calls" &&
  fail "a stubbed run reaches the reboot path"
pass "xpadneo builds against linux-asahi-headers on Apple Silicon"
