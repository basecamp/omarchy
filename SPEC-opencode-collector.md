# Spec: OpenCode Agent Usage Collector

## Overview

Add an `omarchy-agent-usage-opencode` collector (Python) to `bin/` that
prints a display-ready JSON record for the `omarchy.agents` panel. No plugin
QML files need changing — the panel discovers agents from JSON records in
`~/.local/state/omarchy/agents/usage/`.

The collector replaces the old PR's
`shell/plugins/model-usage/scripts/opencode_usage_scanner.py` and
`shell/plugins/model-usage/providers/OpenCode.qml`.

## Reference

- **Codex collector** (`bin/omarchy-agent-usage-codex`) — closest analogue:
  scans Pi sessions, native session files, and opencode sessions for tokens
  on the Codex subscription. The OpenCode collector follows the same pattern
  for its own provider tags.
- **Claude collector** (`bin/omarchy-agent-usage-claude`) — also a good
  reference for Anthropic OAuth limits, though OpenCode has no equivalent.
- **`bin/omarchy-agent-usage-update`** — the orchestrator that runs every
  `bin/omarchy-agent-usage-*` it finds. No changes needed here.
- **`shell/plugins/agents/README.md`** — full panel contract.

## Data Sources

1. **Pi session transcripts** (`~/.pi/agent/sessions/`)
   - Uses `rg` to find assistant messages tagged with an OpenCode provider
     (`opencode`, `opencode-go`, `opencode-zen-openai`)
   - Extracts per-message: input/output/cache tokens, model, timestamp
   - Every message becomes one "prompt"

2. **OpenCode CLI SQLite database** (`~/.local/share/opencode/opencode.db`)
   - Queries assistant messages where `providerID` matches OpenCode routes
   - Extracts per-day aggregated: input/output/reasoning/cache tokens, model,
     session ids
   - CLI sessions contribute to day totals and session counts but are not
     counted as prompts (same as Codex collector)

3. **No rate limits / tier RPC**
   - OpenCode has no public API for usage limits, plan tier, or balance
   - The record will have `limits: []` and `tierLabel: ""`
   - `hasLocalStats: true`, `hasPromptStats: true`

## Route Routing (Zen / Go)

Messages are tagged by provider in both data sources:

| Provider ID / tag | Route | Notes |
|---|---|---|
| `opencode` | `zen` | Zen subscription (API key) |
| `opencode-zen-openai` | `zen` | Zen subscription via OpenAI compatible |
| `opencode-go` | `go` | Go subscription |
| anything else | — | BYOK / direct — excluded from OpenCode |

Messages with a non-matching or absent provider tag are skipped.

## Record Contract

Each collector prints one JSON record to stdout. Both records follow the
same schema as Codex/Claude records (the standard omarchy.agents contract):

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | int | `1` |
| `id` | string | `"opencode-zen"` or `"opencode-go"` |
| `name` | string | `"OpenCode Zen"` or `"OpenCode Go"` |
| `updatedAt` | ISO 8601 | UTC timestamp |
| `ready` | bool | `true` |
| `hasLocalStats` | bool | `true` |
| `hasPromptStats` | bool | `true` — Pi messages are prompt-scoped |
| `todayPrompts` | int | Pi assistant messages today for this route |
| `todaySessions` | int | Unique session keys today for this route |
| `todayTotalTokens` | int | Sum of all tokens today for this route |
| `todayTokensByModel` | dict | `{ "model-id": count }` today for this route |
| `recentDays` | array | Last 7 days, `{ date, messageCount }` |
| `totalPrompts` | int | All-time Pi assistant messages for this route |
| `totalSessions` | int | Unique session keys all-time for this route |
| `activeDays` | int | Days with any usage for this route |
| `activeDates` | array | Sorted date strings — enables cross-device merge |
| `modelUsage` | dict | `{ "model": { inputTokens, outputTokens, cacheReadInputTokens, cacheCreationInputTokens } }` |
| `retryAdvised` | bool | Not set — no limits endpoint to retry |
| `limits` | array | `[]` — no API for rate limits |
| `tierLabel` | string | `""` — no tier info |
| `usageStatusText` | string | Empty — no auth needed |
| `authHelpText` | string | Empty — no auth needed |

## Design Decision: Two Records, Shared Base

**Chosen approach: Option B — two separate records, one shared Python base.**

Rationale: Zen (API-key, pay-per-token) and Go (subscription, rate-limited)
are fundamentally different billing models. The panel treats each JSON
record as a separate tab, so two records gives each its own space with
independent enable/disable, future limits, and auto-hide when unused.

A record with all-zero stats is still written to disk, but the panel's
`providerHasData()` filter drops it — so only the route(s) with actual
usage appear as tabs.

Implementation structure:

```
bin/opencode-usage-base.py              ← shared scanning logic, --route flag
bin/omarchy-agent-usage-opencode-zen    ← thin shell wrapper → base --route zen
bin/omarchy-agent-usage-opencode-go     ← thin shell wrapper → base --route go
```

The orchestrator (`omarchy-agent-usage-update`) discovers the two wrapper
scripts by glob pattern, runs each independently, and writes
`opencode-zen.json` and `opencode-go.json` to the usage directory. The
shared base is not matched by the glob (no `omarchy-agent-usage-` prefix),
so it is never invoked directly.

## Assets

The old PR already has SVG icons at:
- `shell/plugins/model-usage/assets/opencode.svg` (dark variant)
- `shell/plugins/model-usage/assets/opencode-light.svg` (light variant)

The agents panel resolves marks by provider id (`assets/<id>.svg` plus an
optional `assets/<id>-light.svg` twin for light surfaces), so the mark must
be shipped under each route's id:

- `shell/plugins/agents/assets/opencode-zen.svg` + `opencode-zen-light.svg`
- `shell/plugins/agents/assets/opencode-go.svg` + `opencode-go-light.svg`

The plain `opencode.svg` / `opencode-light.svg` copies are left in place as
the shared source of the mark.

## Graceful Degradation

- **Without `rg`** — Pi session scanning falls back gracefully (no match,
  no results)
- **Without the `opencode` CLI** — the SQLite database scan is skipped; Pi
  session scanning continues (same degrade pattern as Codex)
- **Without Pi sessions** — `~/.pi/agent/sessions/` missing: Pi scan is
  silent; OpenCode CLI scan still runs
- **Without either** — record prints `todayPrompts: 0, totalSessions: 0`
  etc., which `providerHasData()` evaluates as false, so the panel hides
  the tab automatically

## Testing

Create `test/shell.d/agent-usage-opencode-test.sh` with:

1. Same fixture structure as the old scanner test: fake `opencode` CLI,
   fake Pi sessions with per-route transcripts
2. Run the base Python script with `--route zen` and `--route go`
3. Assertions for each route: totals, session counts, prompt counts,
   BYOK exclusion, route isolation, graceful degrade without CLI
4. Standard contract assertions: valid JSON, schemaVersion, id, name,
   ready, hasLocalStats, hasPromptStats, no routeData, empty limits

## Open Questions

1. **Zen/Go split approach** — which option (A/B/C) to implement?
2. **Record `id`** — if not option A, what `id` values for route-specific
   records?
3. **Too-few records edge case** — a Pi user with no opencode sessions
   would have `todayPrompts: 0` before the first scan picks up data; the
   panel hides it. Is that acceptable for the first day?
4. **Kol / light assets** — the old PR's SVGs have simple geometric shapes;
   might want a more distinct mark than `opencode.svg` and
   `opencode-light.svg` to differentiate from existing assets
5. **Existing Pi scan filter** — should Pi messages from the opencode
   `provider` tag also contribute toward the Codex collector? They
   currently contribute to OpenCode via this collector AND to the general Pi
   message scan in the Codex collector if the provider is `opencode-codex`.
   The old scanner used `rg` with exact provider matches so there's no
   overlap, but worth verifying.

## Implementation Plan

1. Create `bin/omarchy-agent-usage-opencode` (Python, ~200-250 lines)
   - Adapt old scanner, strip QML-aware `routeData`
   - Use `local_day`, `number`, `model_name`, `runtime_env` helpers from old
     scanner (same pattern as Codex collector)
   - Scan Pi sessions for OpenCode provider tags
   - Query opencode CLI DB for session-level usage
   - Print standard record contract JSON
2. Copy SVG assets to `shell/plugins/agents/assets/`
3. Create test file `test/shell.d/agent-usage-opencode-test.sh`
4. Run tests with `./test/shell`
5. Verify the panel picks up the record:
   - `omarchy agent usage-update`
   - Check `~/.local/state/omarchy/agents/usage/opencode.json` exists
   - Open the agents panel and confirm the tab appears
