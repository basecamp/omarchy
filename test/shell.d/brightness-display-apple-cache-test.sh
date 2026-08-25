#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Stubs on PATH: drop sudo so asdcontrol runs directly, record every asdcontrol
# invocation, make detection deterministic by having --detect report no device,
# and no-op the OSD. On a host without any /dev/*hiddev* node the wrapper's
# detect_apple_display_device returns before it ever runs asdcontrol, so the
# reject cases assert on the negative: a refused cache value is never handed to
# `asdcontrol <dev> -- <step>`. Blind-trust validation would hand it over and be
# caught here.
stub_dir="$TMPDIR/stubs"
mkdir -p "$stub_dir"

asd_log="$TMPDIR/asdcontrol.log"

cat >"$stub_dir/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$stub_dir/sudo"

cat >"$stub_dir/asdcontrol" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >>"$asd_log"
# --detect reports nothing, so detection never yields a device.
if [[ \$1 == "--detect" ]]; then
  exit 0
fi
# A brightness read (a lone device arg) returns a plausible value; a set
# (<device> -- <step>) just succeeds.
if [[ \$# -eq 1 ]]; then
  printf '%s: BRIGHTNESS=30000\n' "\$1"
fi
exit 0
STUB
chmod +x "$stub_dir/asdcontrol"

cat >"$stub_dir/omarchy-osd" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$stub_dir/omarchy-osd"

run_wrapper() {
  # $1: value for XDG_RUNTIME_DIR ("" means unset); remaining args go to the wrapper.
  local xdg="$1"
  shift
  : >"$asd_log"
  if [[ -n $xdg ]]; then
    XDG_RUNTIME_DIR="$xdg" PATH="$stub_dir:$ROOT/bin:$PATH" \
      omarchy-brightness-display-apple "$@" 2>&1 || true
  else
    env -u XDG_RUNTIME_DIR PATH="$stub_dir:$ROOT/bin:$PATH" \
      omarchy-brightness-display-apple "$@" 2>&1 || true
  fi
}

# --- A cache value that is not a hiddev character device is rejected ----------
xdg_dir="$TMPDIR/xdg"
mkdir -p "$xdg_dir"
cache_file="$xdg_dir/omarchy-brightness-display-apple.device"

regular_file="$TMPDIR/not-a-device"
: >"$regular_file"

for poison in "/dev/null" "$regular_file" "/tmp/omarchy-evil"; do
  printf '%s\n' "$poison" >"$cache_file"
  output=$(run_wrapper "$xdg_dir" "+5%")
  if grep -qF -- "$poison -- +5%" "$asd_log"; then
    fail "wrapper handed a non-hiddev cache value to asdcontrol: $poison" "$output"
  fi
done
pass "wrapper rejects a cached path that is not a hiddev character device"

# NOTE: the complementary arm (a cache value that DOES match /dev/hiddev* but is
# not a character device) cannot be built without root -- only real device nodes
# live under /dev. It is covered by the -c test and exercised below only when a
# real hiddev node happens to be present.

# --- A legitimate cached hiddev node is trusted (only where HW is present) ----
real_hiddev=""
for candidate in /dev/usb/hiddev* /dev/hiddev*; do
  if [[ -c $candidate ]]; then
    real_hiddev="$candidate"
    break
  fi
done
if [[ -n $real_hiddev ]]; then
  printf '%s\n' "$real_hiddev" >"$cache_file"
  run_wrapper "$xdg_dir" "+5%" >/dev/null
  grep -qF -- "$real_hiddev -- +5%" "$asd_log" ||
    fail "wrapper did not trust a valid cached hiddev node: $real_hiddev"
  pass "wrapper trusts a cached hiddev character device without re-detecting"
else
  pass "no /dev/hiddev* character device present; skipping the valid-cache case"
fi

# --- With no XDG_RUNTIME_DIR, the predictable /tmp cache is not consulted ------
# Guard on the real path not pre-existing so we never clobber a live cache, and
# remove what we create. Old code read /tmp and would hand /dev/null to
# asdcontrol; new code has no cache path at all when XDG_RUNTIME_DIR is unset.
tmp_cache="/tmp/omarchy-brightness-display-apple.device"
if [[ -e $tmp_cache ]]; then
  pass "$tmp_cache already exists on this host; skipping the /tmp-fallback case"
else
  printf '%s\n' "/dev/null" >"$tmp_cache"
  output=$(run_wrapper "" "+5%")
  used=1
  grep -qF -- "/dev/null -- +5%" "$asd_log" || used=0
  rm -f "$tmp_cache"
  (( used == 0 )) ||
    fail "wrapper consulted the world-writable /tmp cache with no XDG_RUNTIME_DIR" "$output"
  pass "wrapper ignores the /tmp cache path when XDG_RUNTIME_DIR is unset"
fi
