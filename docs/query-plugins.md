# Live query plugins for the Omarchy menu

This adds an **extensible plugin system** that surfaces Alfred/Raycast-style inline results in the Omarchy launcher (`omarchy.menu`). Type into the search box and registered plugins run a command and insert a result row — below the normal search matches, in a **Results** section (at the top whenever nothing else matches) — as you type. Press Enter to act on the top result.

It ships with two built-in plugins (Calculator and Web search). **Anyone can add their own plugins** without touching the source: drop a JSON file in their config and the menu picks it up live (hot-reloaded, no restart).

## Shipped plugins

- **Calculator** (`omarchy.query.calc`) — type an expression (`2+2`, `sqrt(9)`, `pi*2`, `2^10`) and the result appears as `2+2 = 4`. Enter copies the bare result (`4`) to the clipboard and closes the menu.
- **Web search** (`omarchy.query.web`) — offered as a fallback for every query, including arithmetic (it sits one arrow-down below the calculator result). Enter opens it in your default browser as a web app. Bare `http(s)://` URLs pass straight through, so Enter opens the URL itself. Providers: `google` (default), `duckduckgo`, `bing`, `amazon`, `youtube`, `github`, `wikipedia` — e.g. `youtube omarchy` searches YouTube.

## Writing your own plugin

Plugins live in `~/.config/omarchy/query-plugins.json` (a JSON array). The menu watches the file and reloads on save — no shell restart needed. Built-in plugins keep their ids; your plugins merge in by `id` (same id overrides a built-in).

### Schema

| Field | Meaning |
|---|---|
| `id` | Unique plugin id (string, e.g. `com.example.currency`). |
| `kind` | `math`, `web`, `copy`, `run`, or `snippet`. Decides WHEN it fires. |
| `label` | Fallback display name. |
| `i18n` | `{ "en": "...", "es": "..." }` localized names. |
| `icon` | One of: a bundled key (`calc`, `search`); an absolute/relative **path** to an image (`/home/you/icons/foo.svg`, `~/icons/foo.png`); or a Nerd Font **glyph** (`󰅌`). Paths/images always render; glyphs depend on the active font. |
| `command` | Executable to run; the typed query is passed as its only argument. Built-in plugins resolve this under `$OMARCHY_PATH/bin`; user plugins run it exactly as configured — an absolute path, or a name resolved through `PATH`. |
| `action` | `copy` copies the result to the clipboard; `run` executes the command on Enter (for `web` plugins, Enter opens the resolved URL in a browser web-app instead). |
| `keyword` | For `copy`/`run`/`snippet`: only fire when the query starts with this prefix. |
| `enabled` | `false` disables the plugin. |
| `language` | `en` or `es`; language of the result's detail text. |

`kind` firing rules:

- `math` → only when the query looks like arithmetic (has a digit + operator/`.`/parens).
- `web` → always, as the fallback (including for arithmetic and bare URLs).
- `copy`/`run`/`snippet` → only when the query starts with `keyword`.

Result rows are ranked math first, keyword plugins next, web last, so the calculator result is the default and search is one arrow-down away.

### Example: a currency converter (run)

```json
[
  {
    "id": "com.example.currency",
    "kind": "run",
    "label": "Convert currency",
    "i18n": { "en": "Convert", "es": "Convertir" },
    "icon": "~/icons/currency.svg",
    "command": "my-currency-cli",
    "action": "run",
    "keyword": "usd ",
    "language": "en"
  }
]
```

Typing `usd 100 eur` runs `my-currency-cli "usd 100 eur"` and shows the result; Enter runs the command again with the same query.

### Example: a copy-to-clipboard keyword plugin (copy)

```json
[
  {
    "id": "com.example.clip",
    "kind": "copy",
    "label": "Clipboard",
    "i18n": { "en": "Copy text", "es": "Copiar texto" },
    "icon": "󰅌",
    "command": "echo",
    "action": "copy",
    "keyword": "> "
  }
]
```

Typing `> hello` shows `hello` with the localized plugin name as its detail; Enter copies `hello`.

### Example: a translator (web-style)

```json
[
  {
    "id": "com.example.translate",
    "kind": "web",
    "label": "Translate",
    "i18n": { "en": "Translate", "es": "Traducir" },
    "icon": "search",
    "command": "omarchy-query-web",
    "args": "url",
    "action": "run",
    "keyword": "tr "
  }
]
```

## Per-plugin preferences

`~/.config/omarchy/extensions/query-plugins-prefs.jsonc` overrides enabled/language per plugin (JSONC: comments are allowed and stripped before parsing):

```jsonc
{
  "plugins": {
    "omarchy.query.web": { "enabled": false },
    "com.example.clip":   { "language": "es" }
  }
}
```

## Security

The calculator evaluates expressions with a Python `ast` sandbox: only numeric literals, `+ - * / // % **`, unary minus, parentheses, and a small set of math functions/constants (`sqrt`, `sin`, `pi`, `e`, …) are allowed. Attribute access, imports, calls to unknown names, lambdas, and comprehensions are rejected — so pasting `os.system(...)` returns an error instead of executing.

Web search and `run`-action plugins execute the configured `command` with the query as an argument; only install plugins you trust, as with any shell command.

## Roadmap: QML widgets (planned, not yet implemented)

The JSON/command format above covers the common cases (calc, search, snippets, converters) and is testable in CI. The longer-term goal is for this hook to also host **rich QML widgets** inside the menu — a plugin could render an expanded card, a chart, or multiple custom rows, not just a single text row.

The planned design builds on Omarchy's existing plugin system (`services/PluginRegistry.qml`, which already loads QML entry points from `~/.config/omarchy/plugins/<id>/`):

- A new plugin **kind** (e.g. `menu-query`) in the manifest, with an entry point pointing at a QML file inside the plugin directory.
- The menu delegate renders that entry point through a `Loader`, passing the live `query` text as a property and receiving results/actions back.
- `Loader.onStatusChanged` isolates errors: a broken third-party widget falls back to a plain text row instead of breaking the whole menu.

To keep today's format forward-compatible, plugin definitions **reserve** the field `widget` (path to a QML file, relative to the plugin directory or absolute). It is ignored by the current implementation; when the QML-widget kind lands, the same JSON/manifest files will keep working unchanged.
