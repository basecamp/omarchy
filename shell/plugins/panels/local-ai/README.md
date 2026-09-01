# Local AI

One button on the bar for local models. The widget detects hardware, shows
the recommended [local-ai-registry](https://github.com/0xSero/local-ai-registry)
recipe for it (plus up to four alternatives), and runs one validated model
at a time in one labeled Docker container on a loopback OpenAI endpoint.
The QML renders purely from `omarchy local ai snapshot` — no model names,
launch flags, stats, or fixed colors. `bin/omarchy-local-ai` is the
controller; each library under `lib/` owns one concern: snapshot state,
hardware scan, registry gate, container runtime, agent wiring, and
lifecycle workers.

Put it on the bar with `omarchy bar put omarchy.local-ai --before omarchy.agents`;
drop it with `omarchy plugin disable omarchy.local-ai`. The icon is an empty
circle until a model is accepted, then filled. Left-click opens the popup:
one click loads (the download size is shown first — nothing lands on disk
without that click), one click unloads, "Open agent" or right-click opens
the Omarchy default agent on the running model (Pi and Oh My Pi get it
passed explicitly; other agents launch through `omarchy-agent`), and "Share
on Tailscale" publishes the endpoint on the user's tailnet — unload always
unpublishes it.

## Commands

`omarchy local ai` routes into the controller: `load <recipe>` (download if
needed, then run), `unload`, `open-agent [name]`, `share`, `scan`,
`download`, `run`, `switch`, `remove <recipe>`, `default` (make the running
model both agents' default), `snapshot`.

```
uninitialized -> scanning -> idle
idle -> downloading -> starting -> ready      # load
downloaded|idle -> starting -> ready          # run
ready -> switching -> ready                   # rollback restores the previous model
ready -> unloading -> idle
any -> error
```

## Trust and safety

`scan` checks out the registry at the commit in `registry.pin` — the trust
root is a revision reviewed with this plugin. A recipe only launches if it
is `validated`, pins its image by `@sha256` and its weights by full commit
hash, and every mount resolves under the managed cache
(`${MODEL_ROOT}`/`${CACHE_ROOT}`) or the registry checkout. Host networking,
multi-node launches, unknown placeholders, and CUDA-graph disabling flags
are refused with the reason. The recommended model is the registry-flagged
recipe for the matched hardware, or the first runnable one. Only containers
labeled `io.omarchy.local-ai=1` are ever adopted, started, stopped, or
removed; the endpoint binds `127.0.0.1` and is only reachable further via
an explicit `tailscale serve` toggle that unload reverts. Ready means
accepted: model identity, a real chat completion, and a real `shell` tool
call for tool recipes.

On run, an `omarchy-local` provider is written into `~/.pi/agent/models.json`
and `~/.omp/agent/models.yml` (the file Oh My Pi actually reads; a
hand-written YAML is never touched — the snapshot reports that agent as
`manual`). The default provider changes only via the explicit `default`
command; unload deletes exactly what run wrote.

## Tests

`./test/shell.d/local-ai-test.sh` — 34 cases against an isolated temp
registry with docker, curl, tailscale, and hardware shims. No GPU, network,
or Docker daemon involved.
