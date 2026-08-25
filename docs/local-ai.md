# Local AI

How Omarchy serves a local model and wires it into the coding agents. User-facing documentation lives in `manual/17-ai.md`; this page is the reference for the catalog contract and the moving parts.

## Shape

Three desktop surfaces (the menu, the bar panel, the terminal) call the `omarchy-ai-*` commands in `bin/`; the commands drive one Docker container (`omarchy-local-ai`) bound to `127.0.0.1:12434` and edit the agent configs under `~/.pi/agent` and `~/.omp/agent`. There is no daemon: Docker's `--restart unless-stopped` is the supervisor, and the state marker `~/.local/state/omarchy/local-ai/recipe.json` is what every surface keys off — menu guards test its existence, the bar panel hides without it, and `omarchy ai status` exits 2 when it is missing.

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
| `image` | pinned OpenAI-compatible serving image |
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
