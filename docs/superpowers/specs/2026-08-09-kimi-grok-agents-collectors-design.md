# Kimi + Grok collectors for the agents plugin — design

Date: 2026-08-09
Status: Approved
Branch: `model-usage-kimi-grok` (PR #6477, riallineato)
Base: `origin/quattro` @ `f511cf86`

## Problem

Kimi Code and Grok Build quota and local usage are currently implemented in the
obsolete `model-usage` plugin (`shell/plugins/model-usage/scripts/kimi_usage.py`,
`grok_usage.py`), which no longer exists on `quattro` — the plugin was renamed
to `agents/` and the collectors became standalone `bin/omarchy-agent-usage-<id>`
scripts whose read-only JSON records the panel auto-discovers.

PR #6477 (`model-usage-kimi-grok`) is based on the old plugin and is therefore
`CONFLICTING`. The work must be rewritten in the new architecture, following the
exact shape of `bin/omarchy-agent-usage-claude` and `bin/omarchy-agent-usage-codex`.

## Goals

1. Two new collectors — `bin/omarchy-agent-usage-kimi` and
   `bin/omarchy-agent-usage-grok` — that emit the same display-ready record
   shape as claude/codex.
2. All agents consuming the **same subscription** (pi/omp sessions, native CLI
   transcripts, opencode sessions) counted into **one record**, with strict
   provider attribution (no `api`-prefix fallbacks).
3. No double counting of the same session across sources.
4. Official quota/limits probes (Kimi OAuth `/v1/usages`, Grok `billing`)
   surfaced as `limits[]` windows, plus local per-model token history.
5. Reused assets (`kimi.svg`, `kimi-light.svg`, `grok.svg`, `grok-light.svg`):
   plugins auto-discover providers by record id; the assets and
   provider defaults go into `shell/plugins/agents/`.
6. Update PR #6477 in place (force-push `model-usage-kimi-grok`), not a new PR.

## Architecture

Mirror `omarchy-agent-usage-claude`:

- `scan_local` step reads pi/omp transcripts, native CLI session files, and the
  opencode DB, merging via `merge_stats`-style helpers into per-day and
  per-model buckets.
- A `collect_limits` step probes the official endpoint, cached for freshness
  (`--force`, `--limits-only` identical to claude).
- `main()` prints one JSON record:
  `{schemaVersion, id, name, updatedAt, ready, hasLocalStats, tierLabel,
  usageStatusText, authHelpText, limits, totalPrompts, totalSessions,
  activeDates, activeDays, recentDays, todayPrompts, todaySessions,
  todayTotalTokens, todayTokensByModel, modelUsage}`.

### Timeline / surrogate — provider attribution (agents sharing one subscription)

- pi/omp sessions: assistant messages whose `provider` is exactly `kimi-coding`
  (Kimi) or `xai` (Grok). A `api`-prefix fallback must never be used — matches
  the Claude (#6655, `2a0c7371`) and Codex (#6478) fixes.
- opencode DB: `providerID == "kimi"` / `"xai"` exact match.
- Native CLI Kimi: `~/.kimi-code/sessions/*/session_*/agents/*/wire.jsonl` using
  `usage.record` events (`inputOther` / `output` / `inputCacheRead` /
  `inputCacheCreation`).
- Native CLI Grok: proxy base `https://cli-chat-proxy.grok.com/v1`, credits row
  via `billing?format=credits`, grok-com auth entry in `~/.grok/auth.json`,
  local native transcripts under `~/.grok/sessions/`.

### Dedup cross-source (no double counting)

A single global `seen` set keyed by a normalized per-turn identity derived from
the source kinds:

- pi/omp: `pi:<path>:<message-id>`; native: `native:<session-root>:<usage-key>`.
- The same underlying session must be counted once even when it appears in
  both pi/omp and the native transcript (TDD case).
- opencode: `opencode:<db-session-id>:<provider>:<message-uuid>`.

## Implementation notes

- Kimi OAuth client id `17e5f671-d194-4dfb-9706-5516cb48c098` (public, baked
  into the CLI), credentials `~/.kimi-code/credentials/kimi-code.json`.
- Old tests `model-usage-kimi-scanner-test.sh` / `model-usage-grok-scanner-test.sh`
  are ported to `agent-usage-kimi-scanner-test.sh` /
  `agent-usage-grok-scanner-test.sh`.
- `bin/omarchy-agent-usage-update` globs `$OMARCHY_PATH/bin/omarchy-agent-usage-*`.
  No change needed for discovery.

## Out of scope

- Kimi/Grok sync aggregation (`syncMode`) — unchanged, inherited from the panel.
- The old `model-usage` plugin files are deleted on the branch (replaced by the
  `agents/` design already merged in `quattro`).

## Verification

- `test/shell` green for both new scanners.
- Manual dev run: `./bin/omarchy-agent-usage-kimi` and
  `omarchy-agent-usage-grok` output valid records; a session present in both pi
  and native transcripts adds its cost exactly once.