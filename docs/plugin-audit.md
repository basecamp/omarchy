# Plugin Capability Audit

Read this when working on `omarchy-plugin-audit` or the plugin `capabilities` manifest field.

Shell plugins run unsandboxed inside the long-lived `omarchy-shell` process, with the user's full privileges (see [`omarchy-shell.md`](omarchy-shell.md) and `shell/services/PluginRegistry.qml`). Installing a plugin therefore means running its code. `omarchy-plugin-validate` checks that a plugin is *well-formed* — schema, safe relative entry points, no symlinks, no reserved id. It says nothing about what the plugin's code *does*.

`omarchy plugin audit` fills that gap. It statically reads a plugin's own QML, JS, and shell files and reports the capabilities it can reach — every binary it spawns, network host it contacts, and file it reads or writes — then compares that against the plugin's declared `capabilities`. Anything observed but not declared is surfaced; the headline case is a binary the plugin spawns that it never declared.

The scan skips unit tests and dev specs (`test/`, `tests/`, `__tests__/`, `spec/`, `*.test.*`, `*.spec.*`), since the shell never loads them — they are dev artifacts, not plugin behavior. This is safe: a payload hidden in a "test" file only runs if loadable code references it, and that reference is still scanned.

```bash
omarchy plugin audit ./my-plugin           # audit a folder
omarchy plugin audit acme.weather          # audit an installed plugin by id
omarchy plugin audit acme.weather --json   # machine-readable report
omarchy plugin audit acme.weather --strict # exit non-zero on an undeclared command/host/write or a high risk
omarchy plugin audit --explain             # what the overall risk levels mean
```

Every report ends with one overall **verdict** — `minimal`, `low`, `moderate`, `high`, or `critical` — followed by the specific findings that set it. See [Overall verdict](#overall-verdict) below, or run `omarchy plugin audit --explain`.

This is detection, not enforcement. It does not sandbox anything and it cannot resolve fully dynamic (runtime-computed) commands or paths, nor deeply parse a bundled helper written in another language (Python, Ruby, …) — those are reported as their own risk (`dynamic-command`, `partial-coverage`) rather than silently omitted. Treat a clean audit as "nothing obvious stood out," not "proven safe."

## Declaring capabilities

Add an optional `capabilities` object to `manifest.json`. It is backward compatible: the plugin registry and `omarchy-plugin-validate` ignore unknown manifest fields, so declaring capabilities never changes how a plugin loads. Its only consumer is the audit.

```json
{
  "schemaVersion": 1,
  "id": "acme.weather",
  "name": "Weather",
  "version": "1.0.0",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "capabilities": {
    "commands": ["notify-send"],
    "network":  ["api.weather.example"],
    "reads":    ["~/.config/omarchy"],
    "writes":   ["~/.cache/acme-weather"]
  }
}
```

- `commands` — binaries the plugin spawns, matched by basename. A wrapper like `sudo`, `pkexec`, `env`, or `bash -c` is unwrapped to the command it runs, and binaries named inside an inline shell string are recovered, so declare those too.
- `network` — hosts the plugin contacts. An observed host matches a declared entry exactly or as a subdomain (`api.x.example` is covered by `x.example`).
- `reads` / `writes` — files or directories the plugin touches. A declared entry covers itself and everything beneath it, so a directory declaration covers the files inside it. `~`, `$HOME`, and `Quickshell.env("HOME")` are all normalized to `~` for matching.

A plugin that declares exactly what it uses audits clean. Declaring nothing means every observed capability is reported as undeclared — which is the intended nudge for authors and for a marketplace baseline.

## Overall verdict

The report ends with one level, computed only from what the scan found — a triage signal, not a judgement of intent. A higher level can be exactly what a plugin is meant to do (a VPN plugin spawns a VPN binary), and a lower level is never a proof of safety, only "nothing obvious stood out". The verdict line names the findings that drove the level.

| Level | What set it |
|-------|-------------|
| `minimal` | Spawns no command, contacts no host, writes no file, trips no risk. |
| `low` | Does real work, but every capability it uses is declared and nothing tripped a risk. |
| `moderate` | Reaches something undeclared (command/host/write); a medium risk (inline/dynamic command, a shallowly-scanned helper, base64, a raw socket); a single evasion signal (a concatenated `argv[0]` or a runtime-built URL); or network access paired with reading files or running an interpreter — which holds even when every capability is declared, since declaring a capability does not make it safe. |
| `high` | A high-severity risk on its own (privilege escalation, an autostart/systemd/hypr/crontab write, a credential read, a second Quickshell, a refused git origin), hiding what it does on more than one front at once (e.g. both a concatenated binary name and a runtime-built URL), or a third-party plugin that fails `omarchy-plugin-validate`. |
| `critical` | A pattern dangerous almost regardless of intent — pipe-to-shell, runtime code construction, reading credentials while also reaching the network, or privilege escalation (`sudo`/`pkexec`) combined with network access or a credential read. |

The highest matching rule wins. Hiding a capability raises the level rather than lowering it: a benign plugin rarely needs to assemble a binary name or a host from fragments, so the scan not being able to see the real value is itself the signal. `--strict` (below) fails on any `high` or `critical` verdict and on any undeclared command, host, or write; a `moderate` verdict — a single evasion signal, or a declared-but-exposed-network plugin — is reported but does not hard-fail on its own.

## Exit status

- `0` — the plugin is well-formed (or first-party) and, without `--strict`, always when validation passed. The report is advisory by default.
- `1` — `--strict` only: the plugin reaches a `high` or `critical` verdict, or has an undeclared command, host, or write. A `moderate` verdict and undeclared *reads* are reported but do not fail `--strict` on their own.
- `2` — the target could not be resolved, or a third-party plugin failed `omarchy-plugin-validate`. First-party (`omarchy.*`) plugins skip that gate, since validate deliberately rejects the reserved namespace.

`--strict` is the mode for CI and for a marketplace security baseline: it turns the capability report into a pass/fail gate on a specific commit.

## Provenance

When the plugin folder is a git checkout, the audit reports its `origin` URL and runs it through `omarchy-git-url-check` — the same guard `omarchy-plugin-add` and `omarchy-theme-install` use to refuse a URL that names a transport helper (e.g. `ext::`, which runs a command at clone time). A refused origin is raised as a high-severity `git-url` risk.

## Risk heuristics

Beyond the declared-set diff, the audit flags patterns that are worth a human look regardless of declaration: runtime code construction (`eval`, `Qt.createQmlObject`, a dynamically-sourced `Qt.createComponent`), piping a download into a shell, base64 decoding, privilege escalation via `sudo`/`pkexec`, spawning a second Quickshell process, writing to autostart / systemd-user / hypr / crontab locations, and touching credential material (`~/.ssh`, `~/.gnupg`, `~/.aws`, `.netrc`, shell history, browser secrets, `/etc/shadow`). High-severity risks fail `--strict`.

A second group of heuristics targets *evasion* — code shaped to keep a capability out of the scan's view. `obfuscated-command` fires when `argv[0]` is assembled from string fragments (`["cur"+"l"]`) or set from a variable or call, hiding which binary runs; `computed-url` fires when a URL is built at runtime (`"https://" + host`), hiding the destination. These raise the floor rather than lowering it: one puts the verdict at `moderate`, two together at `high`, because a benign plugin rarely needs to hide either. Because these are static, regex-based heuristics, a determined author can still route around them; the audit raises the cost of shipping obvious malware, it does not replace a runtime sandbox.
