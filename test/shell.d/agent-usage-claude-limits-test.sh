#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

# probe_limits reaches Anthropic, so the reader that interprets its answer is
# exercised on its own: the collector loads as a module and a recorded payload
# stands in for the response.
read_scoped() {
  COLLECTOR="$ROOT/bin/omarchy-agent-usage-claude" PAYLOAD="$1" python3 - <<'PY'
import importlib.machinery, importlib.util, json, os

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

print(json.dumps(collector.scoped_limits(json.loads(os.environ["PAYLOAD"]))))
PY
}

# One model-scoped window, plus everything that must not become a limit: a
# repeat of the same model, a blank name, an unparseable percent, and the
# unscoped session and weekly entries the flat buckets already cover.
scoped=$(read_scoped '{
  "five_hour": { "utilization": 78.0 },
  "seven_day": { "utilization": 12.0 },
  "seven_day_opus": null,
  "limits": [
    { "kind": "session", "percent": 78, "scope": null },
    { "kind": "weekly_all", "percent": 12, "scope": null },
    { "kind": "weekly_scoped", "percent": 17, "resets_at": "2026-08-15T03:00:00+00:00",
      "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null } },
    { "kind": "weekly_scoped", "percent": 99, "scope": { "model": { "display_name": "Fable" } } },
    { "kind": "weekly_scoped", "percent": 5, "scope": { "model": { "display_name": "  " } } },
    { "kind": "weekly_scoped", "percent": "unknown", "scope": { "model": { "display_name": "Opus" } } }
  ]
}')

[[ $(jq -c '.' <<<"$scoped") == '[{"label":"Fable","percent":0.17,"resetsAt":"2026-08-15T03:00:00+00:00"}]' ]] ||
  fail "Claude collector reads a model-scoped limit once and drops unusable entries" "$scoped"
pass "Claude collector reads a model-scoped limit once and drops unusable entries"

# An account with no model-scoped allowance, and an endpoint that never grew
# the array, both keep the session and weekly windows they always had.
for payload in '{"five_hour":{"utilization":78.0},"limits":[{"kind":"session","percent":78,"scope":null}]}' \
  '{"five_hour":{"utilization":78.0},"seven_day":{"utilization":12.0}}'; do
  [[ $(read_scoped "$payload") == "[]" ]] ||
    fail "Claude collector adds no limit when the payload scopes none" "$payload"
done
pass "Claude collector adds no limit when the payload scopes none"
