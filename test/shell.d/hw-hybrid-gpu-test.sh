#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d) || fail "test temp directory is available"
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/cardwire" <<'STUB'
#!/bin/bash

[[ $1 == "get" ]] || exit 64

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

cat <<OUT
Current Mode: ${MODE:-Hybrid}
Available Mode: ${AVAILABLE_MODES:-integrated, hybrid, smart}
OUT
STUB

cat >"$fake_bin/lspci" <<'STUB'
#!/bin/bash

for _ in $(seq "${GPU_COUNT:-1}"); do
  echo "0000:00:02.0 VGA compatible controller: Stub GPU"
done
STUB

chmod +x "$fake_bin"/*

hybrid_gpu() {
  PATH="$fake_bin:$ROOT/bin:$PATH" timeout --kill-after=1s 10s bash "$ROOT/bin/omarchy-hw-hybrid-gpu"
}

hybrid_gpu ||
  fail "hybrid GPU detection sees a laptop hybrid system"
pass "hybrid GPU detection sees a laptop hybrid system"

AVAILABLE_MODES="hybrid, manual" hybrid_gpu
status=$?
((status == 1)) ||
  fail "hybrid GPU detection hides on desktop systems" "exit status: $status"
pass "hybrid GPU detection hides on desktop systems"

FAIL_STATUS=1 GPU_COUNT=1 hybrid_gpu
status=$?
((status == 1)) ||
  fail "hybrid GPU detection sees one GPU as non-hybrid when cardwire cannot answer" "exit status: $status"
pass "hybrid GPU detection sees one GPU as non-hybrid when cardwire cannot answer"

FAIL_STATUS=1 GPU_COUNT=2 hybrid_gpu ||
  fail "hybrid GPU detection counts multiple GPUs when cardwire cannot answer"
pass "hybrid GPU detection counts multiple GPUs when cardwire cannot answer"

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
  fail "hybrid GPU detection stays bounded when cardwired ignores the timeout signal"
((status == 1)) ||
  fail "hybrid GPU detection sees one GPU as non-hybrid when cardwired is wedged" "exit status: $status"
pass "hybrid GPU detection stays bounded when cardwired ignores the timeout signal"

BLOCKED=kill-only GPU_COUNT=2 hybrid_gpu ||
  fail "hybrid GPU detection counts multiple GPUs when cardwired is wedged"
pass "hybrid GPU detection counts multiple GPUs when cardwired is wedged"

cat >"$fake_bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$fake_bin/omarchy-cmd-present"

GPU_COUNT=2 hybrid_gpu ||
  fail "hybrid GPU detection counts GPUs without cardwire"
pass "hybrid GPU detection counts GPUs without cardwire"
