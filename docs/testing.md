# Testing

How the non-graphical test suites are organized: what each runner owns, the
protocol test files speak, and the conventions that keep them runnable on any
machine — including headless CI sandboxes with no compositor. The graphical
acceptance suite is a separate thing that drives a live session in a disposable
VM; see [`agents/skills/acceptance-tests.md`](../agents/skills/acceptance-tests.md).

## Suite map

`./test/all` runs both suites below and keeps going when one fails, so a single
failure cannot hide the other suite behind it. It reports the failed suites at
the end and exits non-zero.

- **`./test/cli`** — one big script, one suite. It owns the CLI router: help
  and group rendering, route resolution, aliases, hidden commands, and the
  guarantee that a trailing `--help` never executes the target. It also owns
  the metadata lint — every `omarchy-*` executable under `bin/` is checked for a
  `# omarchy:summary=` header and against removed or redundant fields — plus
  the theme pipeline: template rendering (`omarchy-theme-set-templates`,
  `omarchy-theme-color`, `omarchy-theme-osc`), the theme sync commands
  (tmux, GNOME, VS Code, Pi, Claude) run against stub binaries and a fake
  `$HOME`, and the theme-state migrations.
- **`./test/shell`** — runs every `test/shell.d/*-test.sh` (except
  `base-test.sh` itself). Each file is an independent suite covering one area:
  a shell plugin, a `bin/` command, a config invariant, a migration. This is
  where new tests go.
- **Acceptance** — everything that needs a real desktop doing real things.
  Deliberately excluded from `./test/all`; it runs in a VM, not the
  development session.

A new shell test only needs the right name: drop `<area>-test.sh` into
`test/shell.d/` and `./test/shell` picks it up automatically. Shared fixtures
live under `test/shell.d/fixtures/`.

## The base-test.sh contract

Every shell test starts the same way:

```bash
#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
```

`base-test.sh` refuses to be executed directly — it is a library. It discovers
the repo root from its own location and exports it as `ROOT`, so tests
reference files as `$ROOT/bin/...` and never depend on the caller's working
directory or an installed Omarchy.

Assertions are TAP-flavored and blunt:

- `pass "description"` prints `ok - description`.
- `fail "description" [detail]` prints the optional detail and
  `not ok - description` to stderr, then **exits the file**. There is no
  counting or continuing within a file: the first failed assertion ends it,
  which keeps later assertions from reporting against state the failure
  already invalidated.
- `require_command <cmd>` fails the file when a needed tool is absent.

The runner compensates for that early exit: `./test/shell` continues past a
failing file and summarizes the failures at the end. Aborting the whole run at
the first bad file once let a single packaging failure mask 114 of 134 files.
Failure granularity is therefore per file inside a run, per assertion inside a
file.

## Compositor-dependent tests

Some tests launch Quickshell or query Hyprland, but the suite must stay green
on headless machines. `require_compositor "description"` handles this: when no
compositor answers it prints `ok - no Wayland compositor; skipping ...` and
exits 0 — a skip is a passing test — and otherwise returns so the file
proceeds.

The probe is more than an environment check, because `WAYLAND_DISPLAY` only
proves the variable was inherited. Sandboxes pass the environment through
while blocking `$XDG_RUNTIME_DIR`, so Quickshell clears a bare variable check
and then aborts inside QGuiApplication — a core dump per launch where a skip
belonged. So `compositor_reachable` checks the socket actually exists, then
asks Hyprland itself (`hyprctl -j monitors`, retried, and only when
`HYPRLAND_INSTANCE_SIGNATURE` makes it askable), since a compositor that died
mid-session leaves its socket behind. When the compositor is reachable,
`require_compositor` also sets `ulimit -c 0`: Quickshell leaves through
`qFatal()` if its connection drops mid-run, and the test should fail without
writing a core dump as debris.

Gate only what needs gating — put `require_compositor` in files whose runtime
half needs a live session, and keep static analysis of the same area in code
that runs unconditionally before or beside it.

## Unit-testing shell JavaScript from bash

The Quickshell plugins keep their logic in plain `.js` modules
(`shell/plugins/menu/MenuModel.js`, `bar/BarModel.js`, ...) that end in a
guarded `if (typeof module !== "undefined") module.exports = {...}` block. QML
imports them directly and ignores the guard; Node loads them as CommonJS. That
dual citizenship is what makes the shell's model logic unit-testable without a
compositor.

`run_node_test` is the bridge: it prepends a JS prelude to a heredoc and pipes
the result into `node`. The prelude mirrors the bash assertion protocol
(`pass`, `fail`, `assert`, `assertEqual`, `assertDeepEqual` — same
`ok`/`not ok` lines, same exit-on-first-failure) and provides `root` (from the
exported `ROOT`), `path`, and `requireFromRoot(relativePath)`:

```bash
run_node_test <<'JS'
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')

const parsed = menu.parseMenuJsonc('{ "items": { "root": { "label": "Go" }, }, }')
assertEqual(parsed.length, 1, 'menu parses JSONC with trailing commas')
JS
```

Roughly a quarter of the shell test files use this to test parsing, merging,
and layout logic as pure functions, reserving compositor-gated tests for what
only a live session can prove.

## Conventions worth copying

- **Stub the world, run the real code.** Tests build a scratch `bin/` of stub
  executables (`sudo`, `tmux`, `gsettings`, helper commands) that log their
  arguments to a file, prepend it to `PATH`, and then run the real script
  under test. Assertions grep the call log and the files the script wrote.
- **Fake `$HOME`, real `$OMARCHY_PATH`.** Anything touching user state runs
  with `HOME` pointed at a `mktemp -d` directory (cleaned up via
  `trap ... EXIT`) and `OMARCHY_PATH="$ROOT"`, so tests exercise the checkout
  without touching the developer's machine.
- **Migrations run directly.** A migration test builds the legacy state in a
  fake `$HOME`, runs `bash -euo pipefail "$ROOT/migrations/<ts>.sh"`, and
  asserts the resulting state — including running it twice to prove
  idempotence, and once against non-legacy state to prove it leaves user
  customization alone.
- **Assert the invariant, not the snapshot.** Config tests pin the property a
  test is named for (this widget stays adjacent to that one) rather than whole
  structures, so unrelated churn does not fail them.
