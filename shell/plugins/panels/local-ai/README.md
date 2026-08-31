# Local AI

One bar icon and one full panel for running validated registry models on
local GPUs. The bar widget and dashboard render only from
`omarchy local ai snapshot`. They never embed model names, launch flags, or
fixed colors.

`Panel.qml` is the bar icon and compact popup. `Dashboard.qml` is the
full-screen recipe panel. `bin/omarchy-local-ai` is the CLI and dispatch. Libraries under `lib/`
own one concern each: snapshot state, hardware scan, registry/safety
gate, container runtime, agent wiring, and lifecycle workers.

## Panel

- **Bar icon** — an empty circle until a model is accepted, then a filled
  one. Left-click opens the compact popup; right-click opens Pi when a
  model is loaded.
- **Compact popup** — current state, GPU rows, Scan, Open Pi, Unload, and
  a link to the full panel. Enter opens the dashboard; Tab moves to the
  neighboring bar panel.
- **Dashboard** — hardware groups, VRAM, the bound endpoint, and every
  matching recipe. `j`/`k` move, Enter downloads/runs/switches the
  selected recipe, `p` opens Pi, Esc closes.

Put it on the bar with `omarchy bar put omarchy.local-ai --before omarchy.agents`.
Drop it with `omarchy plugin disable omarchy.local-ai`.

## Commands

The panel and CLI share one controller. `omarchy local ai` is a thin
router into that script:

```bash
omarchy local ai scan
omarchy local ai download <recipe>
omarchy local ai run <recipe>
omarchy local ai unload
omarchy local ai remove <recipe>   # reclaim disk: delete weights and image
omarchy local ai open-agent pi     # or omp
omarchy local ai default           # make the running model the default agent model
omarchy local ai switch <recipe>
omarchy local ai snapshot
```

```
uninitialized -> scanning -> idle
idle -> downloading -> downloaded
downloaded|idle -> starting -> ready
ready -> switching -> ready     # rollback restores the previous accepted model
ready -> unloading -> idle
any -> error
```

## Agent wiring

`open-agent` launches Pi or Oh My Pi through `omarchy-launch-tui` with
`--provider omarchy-local --model <served>` and a fresh session id. On
run, the controller writes an `omarchy-local` provider into
`~/.pi/agent/models.json` and — because Oh My Pi reads
`models.yml`/`models.yaml` with precedence and only migrates
`models.json` once — into `~/.omp/agent/models.yml` (JSON text, which is
valid YAML). A hand-written YAML file is never touched; the snapshot
reports that agent as `manual` under `active.agents`. The controller
updates `defaultModel` only when `defaultProvider` is already
`omarchy-local`. A missing default is left alone unless you run
`omarchy local ai default`, which points both agents' default at the
running model; unload removes that default again. `snapshot` never
writes agent config. Unload removes that provider.

Downloads persist across unload. `download` refuses to start when the
target filesystem lacks the declared weight size; `remove <recipe>`
deletes a recipe's weights and image (the dashboard shows each
recipe's size before you download it).

## Registry

`scan` clones
[local-ai-registry](https://github.com/0xSero/local-ai-registry) into
`~/omarchy/local-ai` and checks out the commit in `registry.pin`, so
the trust root is a revision reviewed with this plugin, not whatever
`main` says at clone time. Moving the pin is a deliberate change to
that file (set `OMARCHY_AI_REGISTRY_PIN=` empty to track `main`
instead). The catalog reads the sharded discovery index at
`registry/index/recipes.json`. Override the tree with
`OMARCHY_AI_REGISTRY`.

Every recipe must be `status: validated`, pin its image by `@sha256`,
and pin its model revision by full commit hash. Recipes that disable
CUDA graphs or eager-enforce are refused. The controller owns exactly
two registry placeholders — `${MODEL_ROOT}` and `${CACHE_ROOT}` map to
`~/.cache/omarchy/local-ai/{models,cache}` — and refuses any other
placeholder, host networking, or multi-node (`--nnodes`) launch. A
refused recipe still appears in the catalog as `blocked` with its
reason, instead of vanishing. A read-only `${MODEL_ROOT}` mount beyond
the primary weights (for example a speculative-decoding draft model)
must already exist on disk; the reason names the missing path.

The OpenAI-compatible endpoint binds to `127.0.0.1`. Only containers
labeled `io.omarchy.local-ai=1` are adopted, started, stopped, or
removed. A `~/.cache` mount source that contains `..` is refused.

## Tests

```bash
./test/shell.d/local-ai-test.sh
```

The suite uses an isolated temp registry and shims for docker, curl, and
hardware. No GPU, network, or real Docker daemon is involved.
