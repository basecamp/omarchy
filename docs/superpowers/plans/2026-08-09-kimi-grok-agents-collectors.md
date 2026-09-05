# Kimi+Grok agents collectors — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port Kimi Code and Grok Build usage into two standalone collector scripts (`bin/omarchy-agent-usage-kimi`, `bin/omarchy-agent-usage-grok`) in the same display-ready shape as `claude`/`codex`, and land them via PR #6477.

**Architecture:** Each collector is a single Python3 script that (1) scans local usage from pi/omp transcripts, native CLI session files, and the opencode DB — deduping each turn across sources; (2) probes the official quota endpoint and normalizes it into `limits[]`; (3) prints one JSON record the `agents` panel reads (auto-discovery by file name). The plugin needs only asset SVGs and provider defaults; no QML changes.

**Tech Stack:** Python 3 stdlib (`json`, `sqlite3`, `urllib`, `datetime`); bash harness in `test/shell.d/` (`base-test.sh`); `rg` for pi transcript scan; `python3 -m http.server` for endpoint stubs in tests.

## Global Constraints

- Python shebang `#!/usr/bin/python3`; two-space indent; no tabs; repo `bin/` metadata lines (`# omarchy:summary=...`, `# omarchy:args=[--force] [--limits-only]`, `# omarchy:hidden=true`).
- Attribution is exact provider match only, never an `api` prefix: pi/omp `kimi-coding`/`xai`; opencode `providerID` equal `kimi`/`xai`.
- No cross-source double count: a turn logged by the native CLI and also by a pi message must still be counted once.
- Quota vs local never mixed: `limits` come only from the API probe; token totals only from local scan.
- Record JSON keys follow the panel contract (see claude): `schemaVersion, id, name, updatedAt, ready, hasLocalStats, tierLabel, usageStatusText, authHelpText, limits, todayPrompts, todaySessions, todayTotalTokens, todayTokensByModel, recentDays, totalPrompts, totalSessions, activeDates, activeDays, modelUsage`; printed with `sort_keys=True`, one line, exit 0 always.
- Tests: `test/shell.d/*-test.sh` sourcing `base-test.sh`, `require_command jq`, `require_command python3`.
- The `agents` plugin discovers providers from record files, so collectors must write their JSON to stdout; `bin/omarchy-agent-usage-update` writes them to the usage dir by globbing `$OMARCHY_PATH/bin/omarchy-agent-usage-*`.

---

### Task 1: Kimi collector — local scan + dedupe (TDD)

**Files:**
- Create: `bin/omarchy-agent-usage-kimi`
- Create test: `test/shell.d/agent-usage-kimi-scanner-test.sh`

**Interfaces produced:** `scan_local()` → dict (the record stats keys); `normalize_model(raw)` → collapses `kimi-code/k3`, `kimi-k3`, `opencode-go/kimi-k3` into one model key `k3`; `usage_token(usage, snake, camel)`.

- [ ] **Step 1: Write the failing test** (native + pi, one day, no double-count).

```bash
#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.kimi-code/sessions/wd_test/session_aaaa/agents/kimi" \
         "$TEST_HOME/.pi/agent/sessions/wd_test"
now_ms=$(( $(date +%s) * 1000 ))
old_ms=$(( ($(date +%s) - 3 * 86400) * 1000 ))

cat >"$TEST_HOME/.kimi-code/sessions/wd_test/session_aaaa/agents/kimi/wire.jsonl" <<EOF
{"type":"usage.record","model":"kimi-code/k3","usage":{"inputOther":1000,"output":200,"inputCacheRead":300,"inputCacheCreation":0},"time":$now_ms}
{"type":"usage.record","model":"opencode-go/kimi-k3","usage":{"inputOther":500,"output":100,"inputCacheRead":100,"inputCacheCreation":50},"time":$now_ms}
{"type":"usage.record","model":"kimi-code/k2","usage":{"inputOther":50,"output":10,"inputCacheRead":0,"inputCacheCreation":0},"time":$old_ms}
EOF

cat >"$TEST_HOME/.pi/agent/sessions/wd_test/session-pi.jsonl" <<EOF
{"type":"message","id":"pi-1","timestamp":"2026-08-09T12:00:00Z","message":{"role":"assistant","provider":"kimi-coding","model":"k3","usage":{"input":400,"output":100,"cacheRead":50,"cacheWrite":0,"totalTokens":550}}}
EOF

result=$(HOME="$TEST_HOME" KIMI_CODE_HOME="$TEST_HOME/.kimi-code" \
  "$ROOT/bin/omarchy-agent-usage-kimi" --local-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "2800" ]] ||
  fail "Kimi sums native and pi usage without double-counting" "$result"
[[ $(jq -c '.modelUsage.k3' <<<"$result") == '{"inputTokens":1900,"outputTokens":400,"cacheReadInputTokens":450,"cacheCreationInputTokens":50}' ]] ||
  fail "Kimi buckets the k3 model once from native+pi" "$result"
pass "Kimi local scan merges native+pi into one model"
```

Expected sums as asserted: today total = turn1(1000+200+300=1500) + turn2(500+100+100+50=750) + pi(400+100+50+0=550) = **2800**; k3 bucket inputTokens=1000+500+400=1900, outputTokens=200+100+100=400, cacheRead=300+100+50=450, cacheWrite=50. (Older `kimi-code/k2` turn of 60 stays out of today but lands in `recentDays`.)

- [ ] **Step 2: Run test, expect fail (`No such file or directory`).**

Run: `bash test/shell.d/agent-usage-kimi-scanner-test.sh`

- [ ] **Step 3: Implement `bin/omarchy-agent-usage-kimi` (local only).**

Base it on `bin/omarchy-agent-usage-claude` structure; replace the anthropic-specific readers:

- `AGENT_ID="kimi"`, `AGENT_NAME="Kimi Code"`, home = `$KIMI_CODE_HOME` or `~/.kimi-code`.
- `scan_native_wires(base)`: glob `base/sessions/*/session_*/agents/*/usage-*.jsonl`? Follow reference: `*.jsonl` naming `wire.jsonl`, actually `base/sessions/*/session_*/agents/*/wire.jsonl`; read `usage.record` events with usage keys `inputOther`, `output`, `inputCacheRead`, `inputCacheCreation`; model = `normalize_model`.
- `normalize_model(raw)` lower + strip path prefix: `str(raw).rsplit("/")[-1].partition("kimi-")[2] or "kimi-code"` collapsing `kimi-code/k3`,`kimi-k3`,`opencode-go/kimi-k3` → k3.
- `scan_pi(root)`: provider exactly `kimi-coding`, key `pi:<path>:<msgid>`; usage `input`/`output`/`cacheRead`/`cacheWrite`, fallback to `totalTokens` on `input`.
- `scan_opencode(db)`: `providerID == "kimi"` exactly.
- A single `stats` accumulator merges native+pi+opencode counts into repeated `merge` helper (copy claude's `merge_stats`).
- Add `parser.add_argument("--local-only", ...)` disabling the quota probe.
- Print the record using the same shape as `omarchy-agent-usage-claude.main()` (with `"limits": []`, `"tierLabel": "Subscription"`, `"usageStatusText"`, `"authHelpText"`).

- [ ] **Step 4: Run test, adjust the expected numbers to the true reply, confirm green.**

- [ ] **Step 5: Commit.**

```bash
git add bin/omarchy-agent-usage-kimi test/shell.d/agent-usage-kimi-scanner-test.sh
git commit -m "kimi: local usage collector with cross-source dedupe"
```

---

### Task 2: Kimi collector — official quota / limits probe

**Files:**
- Modify: `bin/omarchy-agent-usage-kimi`
- Modify test: `test/shell.d/agent-usage-kimi-scanner-test.sh`

**Interfaces produced:** `normalize_usage(payload)` → `(metrics list, tier string)` with each metric `{label, percent, resetsAt}`; `collect_limits(base_url, home)`.

- [ ] **Step 1: Write the failing quota test** (adds `python3 -m http.server` stub serving `/usages`).

Reuse the old test fixture from `fork/model-usage-kimi-grok:test/shell.d/model-usage-kimi-scanner-test.sh`: credential file shape, `usage` payload with weekly summary + 300 min window. Set `KIMI_CODE_BASE_URL`. Assert `.metrics` labels == `["Weekly limit", "5h limit"]`, `.metrics[0].percent == "0.5"`, `.plan == "Intermediate"`.

- [ ] **Step 2: Run, expect fail on metrics/plan.**

- [ ] **Step 3: Implement `collect_limits()` in the collector.** Copy the quota parsing/normalization from the old `kimi_usage.py` (`usage_row`, `to_metric`, `normalize`, `limit_label`, `reset_at`, `refresh_token`, `refresh_under_lock`) verbatim; integrate `load_token`+`fetch_usages`; cache at `cache_root()/"kimi-limits.json"` with the same freshness pattern as claude. Wire to `limits`, `tierLabel`, `usageStatusText`.

- [ ] **Step 4: Run test, confirm green.**

- [ ] **Step 5: Commit** — `git commit -m "kimi: official quota limits"`

---

### Task 3: Grok collector — local scan + dedupe (TDD)

**Files:**
- Create: `bin/omarchy-agent-usage-grok`
- Create test: `test/shell.d/agent-usage-grok-scanner-test.sh`

**Interfaces produced:** `scan_local()` → dict (record stats keys); Grok native turn model mapping and per-turn peak-token extraction identical to old `grok_usage.py`.

- [ ] **Step 1: Port the failing test.**
  Take `fork/model-usage-kimi-grok:test/shell.d/model-usage-grok-scanner-test.sh`, rename `model-usage-grok-scanner-test.sh` → `agent-usage-grok-scanner-test.sh`, replace the `scanner()` wrapper (lines calling `$ROOT/shell/plugins/model-usage/scripts/grok_usage.py`) with:

```bash
scanner() {
  HOME="$TEST_HOME" GROK_HOME="$TEST_HOME/.grok" _CLI_CHAT_PROXY_BASE_URL="http://127.0.0.1:$PORT" \
    "$ROOT/bin/omarchy-agent-usage-grok"
}
```

  Keep fixture + assertions unchanged:
  - `events.jsonl` maps turn_number→model (`grok-4.5` today, `grok-3` −2 days); `updates.jsonl` `_meta.totalTokens` cumulative → per-turn peak(1200), second turn peak(500).
  - One pi `xai` message today adds full split (input 300 / output 100 / cacheRead 400 / cacheWrite 0, totalTokens 800).
  - Expected: `.todayTotalTokens == "2000"` (1200 + 800), `.totalPrompts == "3"`, `.todayPrompts == "2"`, `.modelUsage["grok-4.5"] == {"inputTokens":1500,"outputTokens":100,"cacheReadInputTokens":400,"cacheCreationInputTokens":0}`, `.modelUsage["grok-3"].inputTokens == "500"`.
  The old `.available`/`error` pre-checks (logged-in) map to the new record's `ready` / `authHelpText` — adjust assertions accordingly.

- [ ] **Step 2: Run test, expect fail (`No such file or directory`).**
  Run: `bash test/shell.d/agent-usage-grok-scanner-test.sh`

- [ ] **Step 3: Implement `bin/omarchy-agent-usage-grok` (local only).** Mirror `omarchy-agent-usage-claude`; replace anthropic readers:
  - `AGENT_ID="grok"`, `AGENT_NAME="Grok Build"`, home = `$GROK_HOME` or `~/.grok`.
  - `scan_native_events(root)`: read `root/sessions/*/session-*/events.jsonl` (map turn_number→model_id) + `updates.jsonl` (`_meta.totalTokens` per promptId, peak per turn); native dedupe key `native:<root>:<turn>`.
  - `scan_pi(root)`: provider exactly `xai`, key `pi:<path>:<message-id>`, usage `input/output/cacheRead/cacheWrite`, fallback to `totalTokens`.
  - `scan_opencode(db)`: `providerID == "xai"` exactly.
  - Aggregate all three via the same `merge_stats` helper copied from claude.
  - Same `--local-only` arg and record shape as Task 1.

- [ ] **Step 4: Run test, adjust numbers to the actual run, confirm green.**

- [ ] **Step 5: Commit.**
  `git add bin/omarchy-agent-usage-grok test/shell.d/agent-usage-grok-scanner-test.sh && git commit -m "grok: local usage collector with cross-source dedupe"`

---

### Task 4: Grok collector — official billing / credits probe

**Files:**
- Modify: `bin/omarchy-agent-usage-grok`
- Modify test: `test/shell.d/agent-usage-grok-scanner-test.sh`

**Interfaces produced:** `collect_limits(proxy_base, grok_home)` → `limits[]` + `tierLabel`; `normalize_billing(payload)` verbatim from old `grok_usage.py` (`PERIOD_LABELS`, fraction 0..1, single-product pool dedupe, `iso_utc` resetsAt).

- [ ] **Step 1: Write the failing billing test** (extends the Task 3 fixture).
  The http.server stub already serves `billing?format=credits` (see Task 3 fixture). Assert:
  - `limits` length 1, `.limits[0].label == "Weekly credits"`, `.limits[0].percent == 0.1`, `.limits[0].resetsAt == "2026-07-28T02:33:55Z"`;
  - `ready` true, `tierLabel` present.
  Old record keys `metrics[].label/percent/resetsAt` map to `limits[]`.

- [ ] **Step 2: Run test, expect fail on limits keys (missing collector).**

- [ ] **Step 3: Implement `collect_limits()`.** Copy verbatim from `fork/model-usage-kimi-grok:shell/plugins/model-usage/scripts/grok_usage.py`: `grok_home`, `proxy_base` (env `_CLI_CHAT_PROXY_BASE_URL`), `load_auth`, `token_expired`, `refresh_under_lock`, `fetch_billing`, `iso_utc`, `PERIOD_LABELS`, `normalize`. Cache result at `cache_root()/"grok-limits.json"` with the same freshness rules as claude. Env override stays for the test stub.

- [ ] **Step 4: Run test, confirm green.**

- [ ] **Step 5: Commit** — `git add -A && git commit -m "grok: official billing limits"`

---

### Task 5: Wire the plugin (manifest defaults + assets)

**Files:**
- Modify: `shell/plugins/agents/manifest.json`
- Add: `shell/plugins/agents/assets/kimi.svg`, `kimi-light.svg`, `grok.svg`, `grok-light.svg`

- [ ] **Step 1: Add provider defaults.**
  In `manifest.json` → `"barWidget"."defaults"."providers"` add `"kimi": { "enabled": true }, "grok": { "enabled": true }` (keep claude/codex/fireworks). Update plugin `description` to mention Kimi and Grok.

- [ ] **Step 2: Copy the SVGs.** On `fork/model-usage-kimi-grok` they live at `shell/plugins/model-usage/assets/`:
```bash
for f in kimi kimi-light grok grok-light; do
  git show "fork/model-usage-kimi-grok:shell/plugins/model-usage/assets/$f.svg" > "shell/plugins/agents/assets/$f.svg"
done
```
  (No QML change: icon lookup already resolves `<id>.svg` from the record `id`.)

- [ ] **Step 3: Commit** — `git add manifest.json shell/plugins/agents/assets && git commit -m "agents: wire kimi and grok default providers and assets"`

---

### Task 6: Integration, install, and PR update

**Files:** nothing new — branch `model-usage-kimi-grok`, PR #6477.

- [ ] **Step 1: Full test run** — `./test/shell` (all `agent-usage-*-scanner-test.sh` green) and `./test/cli`.
- [ ] **Step 2: Manual dev runs** — `OMARCHY_PATH=$PWD ./bin/omarchy-agent-usage-kimi --force` and `./bin/omarchy-agent-usage-grok --force` each emit exactly one JSON line (records `schemaVersion: 1`).
- [ ] **Step 3: Install into `/usr/local/bin`** —
```bash
pkexec install -m 755 bin/omarchy-agent-usage-kimi bin/omarchy-agent-usage-grok /usr/local/bin/
```
  then run `omarchy-agent-usage-update` once so the panel sees the new records.
- [ ] **Step 4: Rebase on upstream** — `git fetch origin && git rebase --onto origin/quattro f511cf86 model-usage-kimi-grok` (or `--continue` if a conflict).
- [ ] **Step 5: Force-push the branch and update PR #6477** — `git push -f fork model-usage-kimi-grok`; rewrite the PR title/body to reflect the new architecture; confirm upstream review/CI.
- [ ] **Step 6: Ask the user whether to merge PR #6477** (do not merge unilaterally).

---

### Verification & acceptance criteria

- `./test/shell` and `./test/cli` green after Tasks 1, 3, 5, 6.
- Kimi record: today tokens = sum of `inputOther+output+inputCacheRead+inputCacheCreation` for each turn-level `usage.record` in `wire.jsonl` with the model normalized (`kimi-code/k3` and `opencode-go/kimi-k3` → `k3`), plus pi `kimi-coding` messages merged into the same model bucket; older `k2` bucketed separately; a native turn also described by a pi message is counted once.
- Grok record: per-turn peak `_meta.totalTokens` from `updates.jsonl` keyed by model in `events.jsonl`; pi `xai` split merged into the same model bucket.
- `limits[]` populated only by the quota/billing probe — never from local scan.
- Both records exit 0 always; degraded (no creds) records carry `ready=false` + `authHelpText` + `hasLocalStats=false` (not an error).
- `manifest.json` providers include kimi/grok; SVGs render in the panel.