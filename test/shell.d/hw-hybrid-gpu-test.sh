#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d) || fail "test temp directory is available"
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/supergfxctl" <<'STUB'
#!/bin/bash

[[ $1 == "-s" ]] || exit 64

case "${BLOCKED:-no}" in
kill-only)
  trap '' TERM
  /usr/bin/sleep 30
  ;;
term)
  /usr/bin/sleep 30
  ;;
esac

((${FAIL_STATUS:-0})) && exit "$FAIL_STATUS"

printf '%s\n' "${SUPPORTED_MODES:-Integrated Hybrid}"
STUB

chmod +x "$fake_bin"/*

# The detector counts display controllers out of sysfs rather than parsing
# lspci, so the GPUs are faked as PCI device directories. Every tree also holds
# an unclassified device, which lspci prints as "Non-VGA unclassified device":
# the old pattern matched the VGA inside Non-VGA and counted it as a GPU.
make_pci_tree() {
  local count=$1 tree="$test_tmp/pci-$1" i

  rm -rf "$tree"
  for ((i = 0; i < count; i++)); do
    mkdir -p "$tree/0000:0$i:02.0"
    printf '0x030000\n' >"$tree/0000:0$i:02.0/class"
  done

  mkdir -p "$tree/0000:80:14.5"
  printf '0x000000\n' >"$tree/0000:80:14.5/class"

  printf '%s' "$tree"
}

hybrid_gpu() {
  PATH="$fake_bin:$PATH" OMARCHY_PCI_DEVICES_PATH="$(make_pci_tree "${GPU_COUNT:-1}")" \
    timeout --kill-after=1s 10s bash "$ROOT/bin/omarchy-hw-hybrid-gpu"
}

hybrid_gpu ||
  fail "hybrid GPU detection sees a supported Hybrid mode"
pass "hybrid GPU detection sees a supported Hybrid mode"

SUPPORTED_MODES="Integrated Vfio" hybrid_gpu
status=$?
((status == 1)) ||
  fail "hybrid GPU detection trusts supergfxctl when Hybrid is unsupported" "exit status: $status"
pass "hybrid GPU detection trusts supergfxctl when Hybrid is unsupported"

FAIL_STATUS=2 GPU_COUNT=2 hybrid_gpu
status=$?
((status == 1)) ||
  fail "hybrid GPU detection hides on an ordinary supergfxctl failure" "exit status: $status"
pass "hybrid GPU detection hides on an ordinary supergfxctl failure"

BLOCKED=term GPU_COUNT=1 hybrid_gpu
status=$?
((status == 1)) ||
  fail "hybrid GPU detection sees one GPU as non-hybrid after a clean timeout" "exit status: $status"
pass "hybrid GPU detection sees one GPU as non-hybrid after a clean timeout"

BLOCKED=term GPU_COUNT=2 hybrid_gpu ||
  fail "hybrid GPU detection counts multiple GPUs after a clean timeout"
pass "hybrid GPU detection counts multiple GPUs after a clean timeout"

BLOCKED=kill-only GPU_COUNT=1 hybrid_gpu
status=$?
((status != 124 && status != 137)) ||
  fail "hybrid GPU detection stays bounded when supergfxd ignores the timeout signal"
((status == 1)) ||
  fail "hybrid GPU detection sees one GPU as non-hybrid when supergfxd is wedged" "exit status: $status"
pass "hybrid GPU detection stays bounded when supergfxd ignores the timeout signal"

BLOCKED=kill-only GPU_COUNT=2 hybrid_gpu ||
  fail "hybrid GPU detection counts multiple GPUs when supergfxd is wedged"
pass "hybrid GPU detection counts multiple GPUs when supergfxd is wedged"

cat >"$fake_bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$fake_bin/omarchy-cmd-present"

GPU_COUNT=2 hybrid_gpu ||
  fail "hybrid GPU detection counts GPUs without supergfxctl"
pass "hybrid GPU detection counts GPUs without supergfxctl"

# The unclassified device in every tree above is the regression: one graphics
# card plus one of those used to count as two and report hybrid.
cat >"$fake_bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$fake_bin/omarchy-cmd-present"

GPU_COUNT=1 hybrid_gpu
status=$?
((status == 1)) ||
  fail "one graphics card beside an unclassified device is not hybrid" "exit status: $status"
pass "an unclassified PCI device is not counted as a graphics card"

# Reading a device's class file does not touch PCI config space, so a suspended
# discrete GPU is not resumed just to answer the menu guard this gate sits in.
# Comments are stripped: the script explains at length why it avoids lspci.
! grep -vE '^[[:space:]]*#' "$ROOT/bin/omarchy-hw-hybrid-gpu" | grep -q 'lspci' ||
  fail "the detector must not resume a suspended GPU to count GPUs"
pass "the detector counts GPUs without waking one"
