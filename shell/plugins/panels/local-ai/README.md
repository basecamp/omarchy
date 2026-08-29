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
omarchy local ai open-agent pi   # or omp
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
`~/.pi/agent` and `~/.omp/agent`. It updates `defaultModel` only when
`defaultProvider` is already `omarchy-local`. A missing default is left
alone. `snapshot` never writes agent config. Unload removes that
provider.

## Registry

`scan` clones or fast-forwards
[local-ai-registry](https://github.com/0xSero/local-ai-registry) into
`~/omarchy/local-ai`. Every recipe must be `status: validated`, pin its
image by `@sha256`, and pin its model revision by full commit hash.
Recipes that disable CUDA graphs or eager-enforce are refused. Override
the tree with `OMARCHY_AI_REGISTRY`.

The OpenAI-compatible endpoint binds to `127.0.0.1`. Only containers
labeled `io.omarchy.local-ai=1` are adopted, started, stopped, or
removed. A `~/.cache` mount source that contains `..` is refused.

## Tests

```bash
./test/shell.d/local-ai-test.sh
```

The suite uses an isolated temp registry and shims for docker, curl, and
hardware. No GPU, network, or real Docker daemon is involved.
