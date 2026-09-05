# Lab workbench

The `omarchy.lab` plugin is a graphical front end to a fully scriptable Lab workbench. Every operation must remain available without the shell through a stable `omarchy lab …` command, and every status or list command must offer `--json` for agents.

## Command contract

1. Checkpoints: `omarchy lab checkpoint create|list|restore|rename|delete`
2. Checkout deployment: `omarchy lab checkout list|status|deploy|sync`
3. Health and telemetry: `omarchy lab health [--json]`
4. Artifact capture: `omarchy lab capture screenshot|record|bundle|compare|list`
5. Network modes: `omarchy lab network status|nat|isolated|offline`
6. Test shortcuts: `omarchy lab action list|terminal|launcher|lock|wake|restart-shell|reload-hyprland|key|run`
7. Resource profiles: `omarchy lab resource status|set light|balanced|full|custom`
8. Gold-image management: `omarchy lab gold status|promote|rebuild`
9. Explicit transfer: `omarchy lab transfer clipboard-to|clipboard-from|push|pull`
10. Scenario runner: `omarchy lab scenario list|validate|run`

Destructive commands require `--yes` when they are non-interactive. Structured output is printed only on stdout; progress and diagnostics go to stderr. Scenario files contain command arrays rather than shell strings.

## Plugin shape

The panel has pages for Console, Develop, Environment, Capture, and Automate. Console keeps the current viewer controls. The other pages consume the same JSON interfaces agents use and invoke only the commands above. Long operations show progress and remain cancellable by closing the panel without killing their detached work.

## Completion checklist

- [x] Named, consistent disk checkpoints with list, restore, rename, and delete
- [x] Host worktree discovery plus deploy/sync and host/guest commit status
- [x] Health severity, IP, uptime, CPU, memory, disk, failed units, Hyprland errors, and guest Omarchy source/version
- [x] Screenshot, timed recording, diagnostic bundle, comparison, artifact list, and clipboard handoff
- [x] NAT, isolated host-only, and offline network modes
- [x] Common graphical-session actions plus arbitrary argument-safe key and session commands
- [x] Light, balanced, full, and bounded custom CPU/RAM profiles
- [x] Gold status, promote-current, and rebuild-from-current-ISO workflows with confirmation
- [x] One-shot clipboard and file transfer in both directions
- [x] Validated saved scenarios with built-in smoke and deploy/capture workflows
- [x] All ten surfaces available in the native plugin
- [x] Focused automated coverage and real VM/UI verification
