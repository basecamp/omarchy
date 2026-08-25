# Local AI

How Omarchy serves a local model and wires it into the coding agents. User-facing documentation lives in `manual/17-ai.md`; this page is the reference for the catalog contract and the moving parts.

## Shape

Three desktop surfaces (the menu, the bar panel, the terminal) call the `omarchy-ai-*` commands in `bin/`; the commands drive one Docker container (`omarchy-local-ai`) bound to `127.0.0.1:12434` and edit the agent configs under `~/.pi/agent` and `~/.omp/agent`. There is no daemon: Docker's `--restart unless-stopped` is the supervisor, and the state marker `~/.local/state/omarchy/local-ai/recipe.json` is what every surface keys off — menu guards test its existence, the bar panel hides without it, and `omarchy ai status` exits 2 when it is missing.

## Architecture decisions

### Keep behavior in the CLI

The menu and bar panel invoke the same `omarchy-ai-*` commands available in a terminal. QML renders the state returned by `omarchy-ai-list --json`; it does not select hardware, interpret recipes, or manage Docker itself. The desktop UI can therefore remain optional, and a broken or disabled panel cannot strand the model server.

### Resolve hardware on the machine

The CLI reads NVIDIA VRAM with `nvidia-smi` and selects from recipes that fit the detected cards. Hardware inventory does not leave the machine. The first version supports NVIDIA GPUs with at least 24 GB of VRAM; AMD and Intel support should arrive as additional hardware and runtime adapters rather than branches in the panel.

### Keep model-specific behavior in recipe data

The catalog owns the image, model source, engine arguments, topology, context window, parser settings, environment, and mounts. The Bash workflow owns selection, validation, lifecycle, and agent wiring. A `scale` map changes recipe data for larger GPU counts without adding model-specific conditionals to the commands.

### Pin recipes before promotion

A recipe is not release-ready until its container image is pinned by digest, its model source is pinned to an immutable revision, and its exact launch arguments have passed completion and speed acceptance on the target hardware. Mutable tags and model heads are acceptable while a recipe is a candidate in a draft, but not as the final shared default.

### Treat recipe sources as a trust boundary

`omarchy-ai-sync` only scans the GitHub accounts named in the shipped catalog. A recipe can select a container image, arguments, environment, and host mounts, so adding a source is a code-review and security decision. The synced catalog is a local cache, the shipped catalog remains the fallback, and this version does not accept arbitrary user-supplied registries.

### Keep serving private by default

Docker publishes one OpenAI-compatible endpoint on `127.0.0.1:12434`; it is not exposed on the LAN or Tailnet. Remote access through Tailscale is a separate capability with its own authentication and disclosure decisions, not an automatic side effect of setup.

### Require a completion before claiming readiness

A listening port and a successful `/v1/models` response only mean the engine has started. Setup records state and wires the agents only after `/v1/chat/completions` returns non-empty model output. This keeps configured, running, and accepted as separate states.

### Merge agent configuration without taking ownership

Setup adds or updates only the `local` provider in Pi and OMP. It selects that provider only when no default exists or Local AI already owns the default, and removal deletes only the configuration it owns. Existing cloud-provider choices survive setup, model switches, and removal.

### Use Docker as the supervisor

Omarchy does not add another daemon. One named container owns the serving process, Docker's restart policy owns process supervision, and the recipe state file records the selected model. Start and stop preserve downloaded weights so users can free VRAM without repeating setup.

## Commands

- `omarchy-ai-setup [recipe] [--dry-run]` — probe VRAM, pick (or take) a recipe, bootstrap Docker and the NVIDIA container toolkit when missing, serve, verify with a real chat completion, then wire pi and omp with a `local` provider. The default provider is claimed only when the agent has none.
- `omarchy-ai-sync` — refresh the catalog cache from GitHub (see Sources below).
- `omarchy-ai-list [--json]` — the one read contract: hardware, serving state, active recipe, and every recipe with a `fits` verdict, sorted largest-first. The bar panel is a thin view over this JSON.
- `omarchy-ai-start` / `omarchy-ai-stop` / `omarchy-ai-toggle` — `docker start`/`stop` on the container; weights stay cached, so loading is quick and unloading frees the VRAM.
- `omarchy-ai-status` — exit 0 running, 1 stopped, 2 not set up.
- `omarchy-ai-logs` / `omarchy-ai-remove` — tail the server; take everything out (container, wiring, state, cached weights — the engine image is kept).

## Catalog

The shipped catalog carries exactly two recipes, named for what they are to the user: `fast` (Qwen3.8 27B, one 24 GB card and up) and `smart` (Qwen3.6 35B, two cards and up). The tier name is the user-facing contract; quantization, serving engine, tensor parallelism, and context window are recipe internals that may change without the choice changing.

Resolution order: `$OMARCHY_AI_CATALOG` (tests), then the synced cache `~/.local/state/omarchy/local-ai/catalog.json`, then the shipped `default/omarchy/local-ai.json`. Recipes are sorted by `[-min_vram_mb, -min_gpus, name]` and the auto-pick takes the first entry that fits — so a multi-GPU box auto-serves `smart` and a single card gets `fast`.

A recipe is pure data describing one `docker run`:

| field | meaning |
|---|---|
| `name`, `label` | tier identifier and human title |
| `min_vram_mb` | per-card fit gate (`nvidia-smi memory.total`) |
| `min_gpus` | how many qualifying cards the recipe needs (default 1) |
| `image` | OpenAI-compatible serving image; pin by digest before promotion |
| `container_port` | port the image serves inside the container (default 8000) |
| `args` | verbatim image command arguments (nothing is injected) |
| `run_args` | extra `docker run` flags (e.g. `--shm-size`) |
| `env` | environment map passed with `--env` |
| `volumes` | host→container mounts; a leading `~` expands to `$HOME` |
| `model` | optional HF repo, used by `remove` to clear the weight cache |
| `served_name`, `context_window`, `thinking_format`, `reasoning` | agent wiring; wiring is skipped when `served_name` is absent |
| `vision` | the model takes images — the agent provider gets `["text", "image"]` input |
| `weights_gb` | optional download-size hint for setup's progress message |
| `scale` | GPU-count overrides, keyed by count (`{"2": {…}, "4": {…}}`) |

`scale` is how one recipe covers 1, 2, and 4 GPUs instead of shipping a variant per box: setup counts the cards that pass `min_vram_mb` and deep-merges the largest step that count reaches over the base recipe (objects merge, scalars and arrays replace). `fast` uses it to raise tensor parallelism and context; `smart` only flips `--tensor-parallel-size`.

## Sources

`sources` in the shipped catalog lists GitHub accounts. `omarchy-ai-sync` scans each account's public repos for an `omarchy-recipe.json` at the repo root (raw fetch off the default branch), validates the minimum fields (`name`, `label`, `min_vram_mb`, `image`), stamps `source: "github:<owner>/<repo>"`, and merges the result over the shipped recipes (remote wins on a shared `name`). Publishing a recipe is therefore: put an `omarchy-recipe.json` next to your Dockerfile and push.

## The panel

`shell/plugins/panels/local-ai/` (id `omarchy.local-ai`) follows the panel pattern: one `Panel.qml` entry that is both the bar icon and the popup. The popup is deliberately small: the serving state with a load/unload button, and the two modes — click the one you want and it serves in a floating terminal. Sync, logs, and removal stay CLI-only. Right-click the icon to toggle the server directly. It polls `omarchy-ai-list --json` every 30s (5s while open) and exposes `refresh` over IPC, which the CLI commands poke after every state change.
