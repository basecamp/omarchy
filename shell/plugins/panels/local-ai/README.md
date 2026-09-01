# Local AI

One bar icon and one full panel for running validated
[local-ai-registry](https://github.com/0xSero/local-ai-registry) recipes on
local GPUs. Both render only from `omarchy local ai snapshot` — no model
names, launch flags, or fixed colors in the QML. `bin/omarchy-local-ai` is
the controller; each library under `lib/` owns one concern: snapshot state,
hardware scan, registry gate, container runtime, agent wiring, and
lifecycle workers.

Put it on the bar with `omarchy bar put omarchy.local-ai --before omarchy.agents`;
drop it with `omarchy plugin disable omarchy.local-ai`. The bar icon is an
empty circle until a model is accepted, then a filled one. Left-click opens
the compact popup, right-click opens Pi, Enter opens the dashboard.
Dashboard: `j`/`k` select, Enter downloads/runs/switches, `p` opens Pi.

## Commands

`omarchy local ai` routes into the controller: `scan`, `download <recipe>`,
`run <recipe>`, `switch <recipe>`, `unload`, `remove <recipe>` (reclaim
disk), `open-agent [pi|omp]`, `default` (make the running model both
agents' default), `snapshot`.

```
uninitialized -> scanning -> idle
idle -> downloading -> downloaded
downloaded|idle -> starting -> ready
ready -> switching -> ready     # rollback restores the previous accepted model
ready -> unloading -> idle
any -> error
```

## Trust and safety

`scan` checks out the registry at the commit in `registry.pin` — the trust
root is a revision reviewed with this plugin, not whatever `main` says at
clone time (set `OMARCHY_AI_REGISTRY_PIN=` empty to track `main`). A recipe
only launches if it is `validated`, pins its image by `@sha256` and its
weights by full commit hash, and every mount resolves under the managed
cache (`${MODEL_ROOT}`/`${CACHE_ROOT}`) or the registry checkout. Host
networking, multi-node launches, unknown placeholders, and CUDA-graph
disabling flags are refused; refused recipes stay visible as `blocked` with
the reason. Only containers labeled `io.omarchy.local-ai=1` are ever
adopted, started, stopped, or removed, and the endpoint binds to
`127.0.0.1`. Ready means accepted: model identity on `/v1/models`, a real
chat completion, and a real `shell` tool call for tool recipes.

On run, an `omarchy-local` provider is written into `~/.pi/agent/models.json`
and `~/.omp/agent/models.yml` (the file Oh My Pi actually reads; a
hand-written YAML is never touched — the snapshot reports that agent as
`manual`). The default provider is never changed except by the explicit
`default` command; unload deletes exactly what run wrote.

## Tests

`./test/shell.d/local-ai-test.sh` — an isolated temp registry with docker,
curl, and hardware shims. No GPU, network, or Docker daemon involved.
