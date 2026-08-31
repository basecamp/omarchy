#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
# The /tmp-fallback case (below) must place its decoy at exactly the fixed path the
# old wrapper would have formed, so it cannot use a random mktemp name. Track whether
# we created it and remove it on exit only then -- never touch a path we did not create.
tmp_cache="/tmp/omarchy-brightness-display-apple.device"
created_tmp_cache=0

cleanup() {
  rm -rf "$TMPDIR"
  # Remove the /tmp decoy only if this test is the one that created it.
  if (( created_tmp_cache )); then
    rm -f "$tmp_cache"
  fi
}
trap cleanup EXIT

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

poisons=("/dev/null" "$regular_file" "/tmp/omarchy-evil")

# The cases above all fail on the pathname prefix, so none of them reaches the -c
# test -- drop `&& -c $cached` from the wrapper and they all still pass. A path
# that matches the hiddev glob but is not a character device is what -c is for,
# and it is the realistic stale cache: the display replugs, the interface
# renumbers, and the cached node is simply gone. Add it only when the host really
# has no such node, so a machine with the display attached cannot fail here.
if [[ ! -e /dev/hiddev999 ]]; then
  poisons+=("/dev/hiddev999")
fi

for poison in "${poisons[@]}"; do
  printf '%s\n' "$poison" >"$cache_file"
  output=$(run_wrapper "$xdg_dir" "+5%")
  if grep -qF -- "$poison -- +5%" "$asd_log"; then
    fail "wrapper handed a non-hiddev cache value to asdcontrol: $poison" "$output"
  fi
done
pass "wrapper rejects a cached path that is not a hiddev character device"

# NOTE: the /dev/hiddev999 case above covers the -c test for a glob-matching path
# that does not exist. The remaining arm -- a path under /dev that exists, matches
# the glob, and is not a character device -- cannot be built without root, since
# only real device nodes live there.

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
# Assert on the open, not on the contents. A decoy holding a rejectable path proves
# nothing: the validation above refuses it whether or not the /tmp fallback is still
# there, so that assertion passes against both wrappers. A FIFO with no writer blocks
# whoever opens it, so a wrapper that consults the path hangs and one that ignores it
# exits -- which separates the two. mkfifo is atomic and fails outright if the path is
# taken, so it neither overwrites a file nor follows a symlink; the fixed path is
# required, being exactly the path the old code would have formed. Clear the flag as
# soon as the decoy is gone, so a concurrent run's decoy cannot be removed by this
# run's EXIT trap.
if mkfifo "$tmp_cache" 2>/dev/null; then
  created_tmp_cache=1
  status=0
  env -u XDG_RUNTIME_DIR PATH="$stub_dir:$ROOT/bin:$PATH" \
    timeout 5 omarchy-brightness-display-apple "+5%" >/dev/null 2>&1 || status=$?
  rm -f "$tmp_cache"
  created_tmp_cache=0
  (( status != 124 )) ||
    fail "wrapper consulted the world-writable /tmp cache with no XDG_RUNTIME_DIR" \
      "it blocked reading the FIFO decoy at $tmp_cache"
  pass "wrapper ignores the /tmp cache path when XDG_RUNTIME_DIR is unset"
else
  pass "$tmp_cache already present or not safely creatable; skipping the /tmp-fallback case"
fi
