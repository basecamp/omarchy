# Model usage

One bar icon and one panel for every AI coding subscription on the machine.
`Panel.qml` owns the bar button and the popup; `Main.qml` owns provider
fan-out and the optional cross-device aggregation; `providers/` holds one
adapter per subscription.

## Panel

- **Hero** — the mark, the tool, and the plan it runs on ("Max 20x", "Pro").
  Auth and endpoint problems replace the plan line and repeat in a card.
- **Subscription switch** — one chip per enabled provider (`h`/`l` or click).
  It appears only when more than one provider is enabled.
- **Limits** — the percentage of each allowance used, a matching meter, and
  the time until the session or weekly window resets.
- **Tokens by day** — one row per day for the last week: day, bar, tokens, with today
  bolded at the bottom. Hover today for its prompt and session count.
- **Tokens by model** — tokens per model with the bar behind each row scaled
  to the heaviest model,
  the same way the weekly chart scales to its busiest day. Hover for the
  input / output / cache split.

A subscription appears only when it is enabled in settings and has actually
recorded usage — on this machine or on a synced one. With one such provider
there is no switch row at all; with none, the module leaves the bar entirely
rather than sitting there with nothing to say. A CLI installed mid-session
shows up at the next refresh, so nothing polls the disk waiting for it.

That self-hiding is why the widget ships in the default bar layout: a machine
that has never run Claude Code or Codex draws nothing, and the icon arrives on
its own the first time a scan finds usage. Drop it with
`omarchy plugin disable omarchy.model-usage`.

## Providers

| Provider | Limits | Local stats |
|---|---|---|
| `claude` | Anthropic's OAuth usage endpoint (5-hour session + 7-day weekly) | `~/.claude/projects` scanned by `scripts/claude_usage_scanner.py`, plus `stats-cache.json` and `history.jsonl` |
| `codex` | `scripts/codex_usage_scanner.py` reading the Codex CLI state | the same scanner |

Claude limits need a signed-in CLI; without credentials the panel says so and
falls back to local stats only.

## Interactions

- Bar icon: left = panel, right = refresh, middle = next subscription.
- Panel: `h`/`l` switch subscription, `j`/`k` scroll, `r` or Enter refresh,
  Tab moves to the neighboring bar panel, Esc closes.
- IPC: `omarchy-shell omarchy.model-usage <open|close|toggle|refresh|next>`.

## Settings

Settings live in the widget's entry in `~/.config/omarchy/shell.json`. The
top-level keys can be set with
`omarchy bar set omarchy.model-usage <key> <value>`:

| Key | Default | What it does |
|---|---|---|
| `refreshIntervalSec` | `900` | How often local scans and snapshots refresh |
| `syncMode` | `"Off"` | `"On"` writes this machine's snapshot and merges the others |
| `syncDir` | `""` | A folder synced by Syncthing, Dropbox, rsync, … |
| `syncFileName` | `<hostname>.json` | This machine's snapshot file |
| `syncDeviceId` | hostname | Stable device name inside the snapshot |

Numbers need `--json`, or they land in `shell.json` as strings:

```bash
omarchy bar set omarchy.model-usage refreshIntervalSec 300 --json
omarchy bar set omarchy.model-usage syncDir '~/Sync/model-usage'
```

Per-provider settings are nested, and `set` writes its key literally rather
than walking a dotted path — so pass the whole `providers` object as JSON (or
edit `shell.json` directly):

```bash
omarchy bar set omarchy.model-usage providers '{
  "claude": {
    "enabled": true,
    "statsPath": "~/.claude/stats-cache.json",
    "credentialsPath": "~/.claude/.credentials.json",
    "projectsPath": "~/.claude/projects"
  },
  "codex": { "enabled": false }
}' --json
```

`enabled` defaults to `true` for both; set it to `false` to hide a
subscription that is installed. The paths above are the defaults.

With `syncMode` on, every `*.json` snapshot in `syncDir` is merged, so today,
the last 7 days, and the all-time totals cover every machine you code on —
active days are unioned by date rather than summed. Rate limits stay
per-account and are never merged.

One caveat on "all-time": the Codex scanner only reads native session files
touched in the last 30 days, so Codex totals and its day count cover that
window. Claude's cover every transcript still on disk.
