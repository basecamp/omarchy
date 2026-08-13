# Shell Functions

Omarchy comes with a set of shell functions to simplify common tasks and encapsulate convoluted parameter calls.

## Compression

- `compress [file/dir]`: Create a tar.gz archive from the file/dir.
- `decompress [file.tar.gz]`: Expand a tar.gz file.

## Drives

- `iso2sd [image.iso]`: Create a bootable drive on an SD card using the referenced iso file and picking the drive interactively.
- `format-drive [device] [name]`: Format an entire disk with a single exFAT partition (which works on Windows and macOS too). Run it without arguments to see the available drives. Be careful!

## Dev layouts

Instant multi-pane development layouts for tmux:

- `tdl [ai]`: Create a Tmux Dev Layout with your editor, an AI agent, and a terminal. Use the agent aliases, like `tdl c` for opencode or `tdl cx` for Claude Code, or pass a second agent to run both, like `tdl c cx`.
- `tds`: Create a Tmux Dev Square with editor, diff watching (via `hunk diff --watch`), terminal, and opencode.
- `tdlm [ai]`: Create a `tdl` window for every subdirectory in the current directory.
- `tsl [count] [command]`: Create a swarm of panes tiled in a grid, all running the same command (great for AI agents).

The same layouts are available for Herdr as `hdl`, `hds`, `hdlm`, and `hsl`.

## Git worktrees

- `ga [branch]`: Create a new worktree and branch next to the current repository and jump into it.
- `gd`: Remove the current worktree and its branch (asks for confirmation first).

## Rsync watchers

- `rsw [source] [destination]`: Start a background watcher that rsyncs source to destination whenever anything changes. The destination can be a remote host, like `rsw ~/Work/app nyc-dev:Work/app`.
- `lsw`: List all active watchers.
- `dsw`: Stop all active watchers.

## SSH Portforwarding

Ideal for doing web development with localhost secure-context privileges against a remote box.

- `fip`: Forward one or more ports from a remote host to localhost via SSH.
- `dip`: Disconnect one or more forwarded ports.
- `lip`: List all active SSH port forwards.

Say you start a dev server on port `3000` on a machine accessible as `nyc-dev`, then you can run `fip nyc-dev 3000` to forward that port, so `localhost:3000` actually reaches `nyc-dev:3000`, but without the need for SSL certificates to establish the secure context needed for testing web sockets or the like.

## SSH reconnection

`ssh` itself is wrapped in a function that cleans up the terminal if a connection dies while a remote tmux, Herdr, or editor has claimed it, and then automatically reconnects when an interactive session drops (Ctrl-C stops the retry loop).
