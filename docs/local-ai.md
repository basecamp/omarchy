# Local AI

How Omarchy serves a local model and wires it into the coding agents. User-facing documentation lives in `manual/17-ai.md`; this page is the reference for the catalog contract and the moving parts. The proposed shared API, registry ownership, safe recipe boundary, and complete interface contract live in [`plans/local-ai-registry/PROPOSAL.md`](../plans/local-ai-registry/PROPOSAL.md) and [`plans/local-ai-registry/INTERFACES.md`](../plans/local-ai-registry/INTERFACES.md).

## Shape

Three desktop surfaces (the menu, the bar panel, the terminal) call the `omarchy-ai-*` commands in `bin/`; the commands drive one Docker container (`omarchy-local-ai`) bound to `127.0.0.1:8000` and edit the agent configs under `~/.pi/agent` and `~/.omp/agent`. There is no daemon: Docker's `--restart unless-stopped` is the supervisor, and the state marker `~/.local/state/omarchy/local-ai/recipe.json` is what every surface keys off — menu guards test its existence, the bar panel hides without it, and `omarchy ai status` exits 2 when it is missing.

## Architecture decisions

### Keep behavior in the CLI

The menu and bar panel invoke the same `omarchy-ai-*` commands available in a terminal. QML renders the state returned by `omarchy-ai-list --json`; it does not detect hardware, interpret recipes, or manage Docker. The desktop UI remains optional, and disabling the panel cannot strand the model server.

### Resolve hardware locally

One hardware snapshot records GPU identity, total and free VRAM, compute capability, Docker readiness, NVIDIA runtime readiness, and free disk. The resolver compares recipes against that snapshot without sending the inventory off the machine. The first adapter supports NVIDIA; AMD and Intel should arrive as additional hardware and runtime adapters rather than panel branches.

### Keep model-specific behavior in recipe data

The catalog owns the image, model source, engine arguments, topology, context window, parser settings, environment, and mounts. Bash owns resolution, validation, lifecycle, and agent wiring. A `scale` map changes recipe data for larger GPU counts without adding model-specific conditionals to the commands.

### Separate candidates from validated recipes

Compatibility only means the hardware can satisfy a recipe. A candidate remains visible for inspection but cannot report `fits: true`, become the automatic choice, or run. Promotion to `validated` requires an immutable image and model revision plus completion and speed evidence on the target hardware.

### Treat recipe sources as a trust boundary

`omarchy-ai-sync` reads only the registries pinned in the shipped catalog. A registry leaf can select a container image, arguments, environment, and host mounts, so adding a registry is a code-review and security decision. Omarchy preserves `validated` only when both the canonical catalog and leaf agree and the catalog marks the leaf launchable by its CLI; everything else remains a candidate.

### Keep serving private by default

Docker publishes one OpenAI-compatible endpoint on `127.0.0.1:8000`; it is not exposed on the LAN or Tailnet. Remote access through Tailscale is a separate capability with its own authentication and disclosure decisions, not a side effect of setup.

### Require a completion before claiming readiness

A running container, listening port, and `/v1/models` response are intermediate evidence. The runner records active state and wires the agents only after the expected served model appears and `/v1/chat/completions` returns non-empty output. Configured, running, ready, and accepted remain distinct states.

### Merge agent configuration without taking ownership

Setup adds or updates only the `local` provider in Pi and OMP. It selects that provider only when no default exists or Local AI already owns the default, and removal deletes only Omarchy-owned configuration. Existing provider choices survive setup, model switches, and removal.

### Keep the runtime behind the recipe adapter

Omarchy does not add another daemon. The current validated registry leaves use Docker, so one named container owns the serving process and Docker's restart policy owns supervision. The registry remains authoritative about the launch contract, while the Omarchy adapter translates it into the local lifecycle and state file. A future native runtime can be added as another validated registry runtime without changing the panel or agent wiring. Start and stop preserve downloaded weights so users can free VRAM without repeating setup.

## Commands

- `omarchy-ai-setup [recipe] [--gpus ids] [--port port] [--dry-run] [--json] [--set-default] [--no-configure]` — resolve a validated recipe, require a ready Docker and NVIDIA runtime, serve, verify with a real chat completion, then wire pi and omp with a `local` provider. `omarchy-ai-run` is the hidden implementation command. The default provider is claimed only when the agent has none.
- `omarchy-ai-doctor [--json]` — diagnose GPU, disk, port, Docker, NVIDIA runtime, and recipe capacity. On a fresh system, install Docker and `nvidia-container-toolkit`, enable and start `docker.service`, then restart Docker after configuring the NVIDIA runtime.
- `omarchy-ai-sync` — refresh the catalog cache from GitHub (see Sources below).
- `omarchy-ai-list [--json]` — the one read contract: one hardware snapshot, serving state, active recipe, and every recipe with compatibility, free-capacity, validation, and `fits` verdicts, sorted largest-first. Only validated recipes can have `fits: true`; the bar panel is a thin view over this JSON.
- `omarchy-ai-start` / `omarchy-ai-stop` / `omarchy-ai-toggle` — `docker start`/`stop` on the container; weights stay cached, so loading is quick and unloading frees the VRAM.
- `omarchy-ai-status` — report `ready`, `loading`, `stopped`, or `not-setup`; exit 0 only when ready, 1 while loading or stopped, and 2 when not set up.
- `omarchy-ai-logs` / `omarchy-ai-remove` — inspect the server logs; remove the container, Omarchy-owned agent wiring, and active state. Cached images and weights are deliberately kept for reuse.

## Catalog

The shipped catalog carries two recipes, named for what they are to the user: `fast` (Qwen3.8 27B, one 24 GB card and up) is validated; `smart` (Qwen3.6 35B, two cards and up) remains a candidate. Candidate recipes stay visible for inspection but cannot be selected or auto-served until they have passed the same completion acceptance gate as validated recipes. The tier name is the user-facing contract; quantization, serving engine, tensor parallelism, and context window are recipe internals that may change without the choice changing.

Resolution order: `$OMARCHY_AI_CATALOG` (tests), then the synced cache `~/.local/state/omarchy/local-ai/catalog.json`, then the shipped `default/omarchy/local-ai.json`. Recipes are sorted by `[-min_vram_mb, -min_gpus, name]` and the auto-pick takes the first validated entry that fits. With the shipped catalog today, supported NVIDIA machines auto-serve `fast`; `smart` remains non-runnable while its status is `candidate`.

A recipe is pure data describing one `docker run`:

| field | meaning |
|---|---|
| `name`, `label` | tier identifier and human title |
| `min_vram_mb` | per-card fit gate (`nvidia-smi memory.total`) |
| `min_gpus` | how many qualifying cards the recipe needs (default 1) |
| `image` | pinned OpenAI-compatible serving image |
| `host_port`, `container_port` | default local endpoint and the port served inside the container |
| `args` | verbatim image command arguments (nothing is injected) |
| `run_args` | extra `docker run` flags (e.g. `--shm-size`) |
| `env` | environment map passed with `--env` |
| `volumes` | host→container mounts; a leading `~` expands to `$HOME` |
| `model` | optional upstream model identifier retained as recipe metadata |
| `served_name`, `context_window`, `thinking_format`, `reasoning` | agent wiring; wiring is skipped when `served_name` is absent |
| `vision` | the model takes images — the agent provider gets `["text", "image"]` input |
| `weights_gb` | optional download-size hint for setup's progress message |
| `source`, `registry_id`, `registry_path` | canonical registry provenance retained by sync |
| `scale` | GPU-count overrides, keyed by count (`{"2": {…}, "4": {…}}`) |

`scale` is how one recipe covers 1, 2, and 4 GPUs instead of shipping a variant per box: setup counts the cards that pass `min_vram_mb` and deep-merges the largest step that count reaches over the base recipe (objects merge, scalars and arrays replace). `fast` uses it to raise tensor parallelism and context; `smart` only flips `--tensor-parallel-size`.

## Sources

`registries` in the shipped catalog pins the GitHub repository, branch, catalog path, and hardware slugs Omarchy trusts. `omarchy-ai-sync` reads the registry's `inference-index/catalog-v1` catalog, fetches the referenced `inference-index/v1` leaves, validates the catalog-to-leaf identity, and atomically translates supported leaves into the local cache. The canonical leaf remains the source of truth for the image, model revision, engine arguments, ports, environment, mounts, capabilities, and validation evidence.

The first adapter imports Docker leaves with bridge networking and self-contained absolute or home-relative mounts. Leaves requiring host networking or registry-relative files are skipped until the adapter can reproduce those contracts safely. Omarchy does not maintain a second model registry, and a synced leaf remains a candidate unless the registry catalog and leaf both mark it validated and `launchable_by_cli` is true.

Public registries need no credentials. For a private registry, sync uses `OMARCHY_AI_GITHUB_TOKEN`, then `GITHUB_TOKEN`, then the active `gh` login when GitHub CLI is installed. Credentials stay outside the catalog and repository. If no configured registry can be refreshed, sync fails without replacing the last good cache; a fresh machine continues to use the shipped catalog.

## The panel

`shell/plugins/panels/local-ai/` (id `omarchy.local-ai`) follows the panel pattern: one `Panel.qml` entry that is both the bar icon and the popup. The popup is deliberately small: the serving state with a load/unload button and the catalog modes. Validated modes that fit can be selected; candidates and incompatible modes remain visible but disabled. Sync, logs, and removal stay CLI-only. Right-click the icon to toggle the server directly. It polls `omarchy-ai-list --json` every 30s (5s while open) and exposes `refresh` over IPC, which the CLI commands poke after every state change.
