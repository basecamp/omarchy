---
name: omarchy-admin
description: >-
  Omarchy system administration: updates, migrations, packages, snapshots,
  bootloader, dev environments. Triggers: omarchy-update, omarchy-migrate,
  omarchy-pkg-*, snapshots, Limine, kernel, AUR, system recovery.
---

<sources>

| What | Read From |
|------|-----------|
| Update logic | `cat $(which omarchy-update)` |
| Migration runner | `cat $(which omarchy-migrate)` |
| Package helpers | `ls ~/.local/share/omarchy/bin/omarchy-pkg-*` |
| All migrations | `ls ~/.local/share/omarchy/migrations/` |
| Install scripts | `~/.local/share/omarchy/install/` |

</sources>

<updates>

```bash
omarchy-update        # Interactive (snapshot → git pull → migrate → restart)
omarchy-update -y     # Non-interactive
```

Channel management:
```bash
omarchy-channel-set stable  # master + stable packages
omarchy-channel-set edge    # master + latest packages  
omarchy-channel-set dev     # dev branch (developers only)
```

</updates>

<migrations>

| Aspect | Value |
|--------|-------|
| Location | `~/.local/share/omarchy/migrations/` |
| Naming | Unix timestamp: `1751134560.sh` |
| State | `~/.local/state/omarchy/migrations/<name>` |

```bash
omarchy-dev-add-migration --no-edit   # MUST use --no-edit flag
omarchy-migrate                        # Run pending
```

</migrations>

<packages>

| Command | Purpose |
|---------|---------|
| `omarchy-pkg-add <pkg>` | Install if missing |
| `omarchy-pkg-drop <pkg>` | Remove if present |
| `omarchy-pkg-install` | Interactive TUI |
| `omarchy-pkg-aur-add <pkg>` | Install from AUR |

</packages>

<snapshots>

```bash
omarchy-snapshot create   # SHOULD run before risky changes
omarchy-snapshot restore  # Boot menu selection
```

</snapshots>

<bootloader>

- Config: `/boot/limine.conf`
- Refresh: `omarchy-refresh-limine`

</bootloader>

<services>

Discover: `compgen -c | grep omarchy-restart`

</services>

<state>

```bash
omarchy-state set reboot-required    # Flag reboot needed
omarchy-state clear <name>           # Clear flag
```

State files: `~/.local/state/omarchy/`

</state>

<dev_environments>

```bash
omarchy-install-dev-env <type>
# Types: ruby, node, bun, deno, go, php, python, elixir, rust, java, zig, ocaml, dotnet, clojure
```

</dev_environments>
