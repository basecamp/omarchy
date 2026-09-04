#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq
require_command timeout

stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT

mkdir -p "$stage/bin"

cat >"$stage/bin/ip" <<'STUB'
#!/bin/bash
printf '1.1.1.1 via 192.0.2.1 dev lo src 192.0.2.2\n'
STUB

cat >"$stage/bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
exit 0
STUB

cat >"$stage/bin/curl" <<'STUB'
#!/bin/bash

for arg in "$@"; do
  if [[ $arg == https://api.fast.com/* ]]; then
    printf '{"targets":[{"url":"https://speed.test/chunk"}]}\n'
    exit 0
  fi
done

printf '%s\n' "$BASHPID" >>"$SPEEDTEST_WORKER_PIDS"
exec sleep 30
STUB

chmod +x "$stage/bin/ip" "$stage/bin/omarchy-cmd-present" "$stage/bin/curl"

run_bounded_speedtest() {
  local direction="$1"
  local elapsed
  local status=0
  local started_at=$SECONDS

  : >"$stage/worker-pids"
  OMARCHY_NETWORK_SPEEDTEST_MAX_SECONDS=2 \
    SPEEDTEST_WORKER_PIDS="$stage/worker-pids" \
    PATH="$stage/bin:$PATH" \
    timeout 6 "$ROOT/bin/omarchy-network-speedtest" "$direction" >"$stage/speedtest.out" 2>"$stage/speedtest.err" || status=$?

  (( status == 0 )) || fail "$direction speed test reaches its internal deadline" "$(<"$stage/speedtest.err")"
  elapsed=$((SECONDS - started_at))
  (( elapsed >= 2 && elapsed < 6 )) || fail "$direction speed test stops near its internal deadline" "elapsed: $elapsed seconds"
  [[ -s $stage/worker-pids ]] || fail "$direction speed test starts traffic workers"

  while IFS= read -r pid; do
    if kill -0 "$pid" 2>/dev/null; then
      fail "$direction speed test reaps traffic workers after its deadline" "worker still alive: $pid"
    fi
  done <"$stage/worker-pids"
}

run_bounded_speedtest down
run_bounded_speedtest up

if OMARCHY_NETWORK_SPEEDTEST_MAX_SECONDS=0 "$ROOT/bin/omarchy-network-speedtest" down >"$stage/invalid.out" 2>"$stage/invalid.err"; then
  fail "speed test rejects a disabled internal deadline"
fi
grep -Fx 'OMARCHY_NETWORK_SPEEDTEST_MAX_SECONDS must be a positive integer' "$stage/invalid.err" >/dev/null ||
  fail "speed test explains an invalid internal deadline"

pass "network speed test bounds traffic independently of its UI parent"
