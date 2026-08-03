#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

stub_bin="$TMPDIR/bin"
mkdir -p "$stub_bin"

# Stub lspci to emit a configurable line.
cat >"$stub_bin/lspci" <<'STUB'
#!/bin/bash
printf '%s\n' "${LSPCI_OUTPUT:-}"
STUB
chmod +x "$stub_bin/lspci"

run_gsp() {
  LSPCI_OUTPUT="$1" PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-hw-nvidia-gsp"
}

run_without_gsp() {
  LSPCI_OUTPUT="$1" PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-hw-nvidia-without-gsp"
}

assert_classified() {
  local line="$1"
  local expect_gsp="$2"
  local expect_without="$3"

  local gsp=1 without=1
  run_gsp "$line" && gsp=0 || gsp=1
  run_without_gsp "$line" && without=0 || without=1

  (( gsp == expect_gsp )) ||
    fail "GSP detection for '$line'" "expected exit $expect_gsp, got $gsp"
  (( without == expect_without )) ||
    fail "no-GSP detection for '$line'" "expected exit $expect_without, got $without"
  pass "'$line' is $(if (( expect_gsp == 0 )); then echo GSP; elif (( expect_without == 0 )); then echo no-GSP; else echo neither; fi)"
}

nvidia="02:00.0 3D controller: NVIDIA Corporation"

# --- Turing MX cards (TU117, same generation as GTX 16xx, have GSP firmware) ---
assert_classified "$nvidia TU117M [GeForce MX550]" 0 1
assert_classified "$nvidia TU117 [GeForce MX450]" 0 1
assert_classified "$nvidia TU117 [GeForce MX570]" 0 1

# --- Pre-Turing MX cards (Pascal GP108/GP107, no GSP firmware) ---
assert_classified "$nvidia GP108 [GeForce MX150]" 1 0
assert_classified "$nvidia GP108 [GeForce MX250]" 1 0
assert_classified "$nvidia GP108 [GeForce MX350]" 1 0

# --- Other Turing+ (already correctly classified by existing patterns) ---
assert_classified "$nvidia TU106 [GeForce GTX 1650]" 0 1
assert_classified "$nvidia AD104 [GeForce RTX 4070]" 0 1

# --- Other pre-Turing (already correctly classified by existing patterns) ---
assert_classified "$nvidia GM200 [GeForce GTX 970]" 1 0
assert_classified "$nvidia GP104 [GeForce GTX 1080]" 1 0

# --- Non-NVIDIA GPU is classified as neither ---
assert_classified "00:02.0 VGA compatible controller: Intel Iris Xe Graphics" 1 1
