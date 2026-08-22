#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

# Codex 0.149 retired the "untrusted" approval policy, and the CLI rejects an
# unknown one before app-server starts. The collector discards app-server's
# stderr and waits for an RPC reply, so that immediate exit surfaced as the
# pending method name — "initialize" — and the panel lost its limits with no
# hint of why. This stub answers the way the CLI does: it validates the policy
# first, and only then speaks the protocol.
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.codex" "$TEST_HOME/bin"

cat >"$TEST_HOME/bin/codex" <<'EOF'
#!/bin/bash

policy=""
while (( $# )); do
  case "$1" in
    -a | --ask-for-approval)
      policy="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

case "$policy" in
  on-request | never) ;;
  *)
    echo "error: invalid value '$policy' for '--ask-for-approval <APPROVAL_POLICY>'" >&2
    exit 2
    ;;
esac

while read -r request; do
  id=$(jq -r '.id // empty' <<<"$request")
  method=$(jq -r '.method // empty' <<<"$request")

  case "$method" in
    initialize)
      jq -cn --argjson id "$id" '{id: $id, result: {}}'
      ;;
    account/read)
      jq -cn --argjson id "$id" '{id: $id, result: {account: {planType: "team"}}}'
      ;;
    account/rateLimits/read)
      jq -cn --argjson id "$id" '{id: $id, result: {rateLimits: {planType: "team", primary: {usedPercent: 53, windowDurationMins: 10080}}}}'
      ;;
  esac
done
EOF
chmod +x "$TEST_HOME/bin/codex"

result=$(HOME="$TEST_HOME" CODEX_HOME="$TEST_HOME/.codex" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  XDG_DATA_HOME="$TEST_HOME/.local/share" PATH="$TEST_HOME/bin:$PATH" \
  "$ROOT/bin/omarchy-agent-usage-codex")

[[ $(jq -c '[.limits[] | {label, percent}]' <<<"$result") == '[{"label":"Weekly (7-day)","percent":0.53}]' ]] ||
  fail "Codex collector reads the window app-server reports" "$result"
pass "Codex collector reads the window app-server reports"

[[ $(jq -r '.tierLabel' <<<"$result") == "team" ]] ||
  fail "Codex collector names the plan app-server reports" "$result"
pass "Codex collector names the plan app-server reports"

# The regression this file exists for: a rejected policy left the panel showing
# "Codex limits unavailable" over the RPC method that never got an answer.
[[ -z $(jq -r '.usageStatusText' <<<"$result") ]] ||
  fail "Codex collector launches app-server with an approval policy the CLI accepts" "$result"
pass "Codex collector launches app-server with an approval policy the CLI accepts"
