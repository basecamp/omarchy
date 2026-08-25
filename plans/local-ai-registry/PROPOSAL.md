# Proposal: Hardware-aware Local AI for Omarchy

## The idea

Omarchy should make running a useful local model feel like installing any other optional system capability.

A user chooses **Local AI**. Omarchy detects the machine, shows two to four models that are known to work on that exact hardware, starts the selected model, proves that it can answer a real request, and connects the Omarchy agent to it. The user should not need to choose an inference engine, quantization, tensor-parallel setting, container image, context limit, or cache layout.

The configuration remains inspectable and overrideable, but it is not the starting point.

## Why this needs a registry

The hard part of local inference is not downloading a model. A working setup is a tested combination of:

- exact hardware and GPU count
- model revision and weight format
- inference engine and version
- container image digest
- launch arguments and runtime limits
- context and concurrency ceilings
- capabilities such as tools, reasoning, and vision
- measured correctness and performance evidence

Those combinations are expensive to discover and easy to get subtly wrong. The project should preserve them as immutable recipes and make them reusable by Omarchy, Ori, Local Studio, and other clients.

This is not a greenfield registry. The existing Inference Index already has hardware-first recipe leaves, catalog, recipe, run, and benchmark schemas, generated hardware pages, promotion states, and accepted evidence. The current Omarchy branch already demonstrates catalog sync and local recipe translation. The work proposed here is to make the boundary smaller and safer: compile the existing evidence into a stable consumer API, then let Omarchy execute only the subset covered by a constrained adapter.

## The user flow

1. Omarchy detects a canonical hardware ID such as `nvidia.rtx-3090.24gb.x1.pcie`.
2. The CLI requests recommendations for that hardware ID and an optional intent such as `balanced`, `fast`, `smart`, or `long-context`.
3. The registry returns two to four validated recipe summaries with a plain-language reason for each recommendation.
4. The user selects a recipe, or accepts the default.
5. The CLI fetches the exact recipe and verifies its schema, status, image digest, model revision, and supported runtime adapter.
6. The CLI checks current local conditions: free VRAM, disk, Docker, accelerator runtime, port availability, and cached weights.
7. Omarchy starts the recipe on loopback and waits for the declared OpenAI-compatible model.
8. Omarchy sends a real chat completion. Capability-specific checks run only for capabilities the recipe advertises.
9. Only after acceptance does Omarchy add the local provider to the agent configuration.

The registry answers **what is known to work on this class of machine**. The local CLI answers **whether this machine can run it right now**.

## Project boundaries

| Module | Owns | Does not own |
| --- | --- | --- |
| Omarchy | Menu, bar surface, installation, local defaults, agent integration | Model-specific launch knowledge |
| Local AI CLI | Hardware detection, API client, local capacity checks, recipe execution, lifecycle, acceptance, agent wiring | Recommendation data or benchmark claims |
| Inference Index | Canonical hardware records, immutable recipes, evidence, promotion state | Running commands on user machines |
| Registry compiler | Schema validation, referential checks, recommendation views, static API artifacts | A mutable production database |
| Registry API | Read-only discovery of hardware, recommendations, recipes, and evidence | Submissions, container execution, user accounts |
| Runtime adapter | Translates a constrained recipe into Docker arguments and local staged files | Arbitrary remote shell execution |
| Speed sweeps | Reproducible performance evidence tied to an exact recipe and protocol | Deciding whether a recipe is safe to launch |

## The simplest architecture

```text
Git repository                         Generated static API

hardware records  ─┐                  /v1/hardware/index.json
model records     ─┼─ validate/build ─/v1/hardware/{id}/recommendations/{intent}.json
recipe leaves     ─┤                  /v1/recipes/{id}.json
evidence records  ─┘                  /v1/recipes/{id}/benchmarks.json
                                               │
                                               ▼
                                      Omarchy Local AI CLI
                                               │
                                local checks → Docker → acceptance
                                               │
                                               ▼
                                        Omarchy agent
```

Git is the source of truth. A deterministic compiler validates the registry and emits static JSON. GitHub Pages can serve the first version directly. There is no database, queue, authentication layer, query processing, or long-running API service in the initial design.

HTTP cache headers and an `ETag` let the CLI retain the last known-good catalog. Omarchy ships a small fallback catalog so setup still works when the network is unavailable.

## Registry structure

```text
registry/
├── hardware/
│   └── nvidia.rtx-3090.24gb.x1.pcie.json
├── models/
│   └── qwen3.8-27b.json
├── recipes/
│   └── qwen3.8-27b-q4km-rtx3090-llamacpp-tp1-r1.json
├── evidence/
│   └── qwen3.8-27b-q4km-rtx3090-llamacpp-tp1-r1/
│       ├── acceptance-2026-08-25.json
│       └── sweep-2026-08-25.json
└── policies/
    └── recommendations.json
```

The existing hardware-first Inference Index can remain the authoring layout. The compiler is the compatibility boundary: it resolves those leaves into the normalized API types in [`INTERFACES.md`](INTERFACES.md). Consumers never scrape Markdown or infer launch commands from directory names.

## Stable identities

Hardware identity must include the properties that change whether a recipe works:

```text
<vendor>.<product>.<memory>.<count>.<topology>

nvidia.rtx-3090.24gb.x1.pcie
nvidia.rtx-3090.24gb.x4.pcie
intel.arc-pro-b70.32gb.x2.pcie
nvidia.dgx-spark-gb10.128gb.x2.roce
```

Friendly aliases such as `rtx-3090` may resolve locally when unambiguous, but the API and evidence use the canonical ID.

A recipe ID names the full immutable compatibility unit:

```text
<model>-<weights>-<hardware>-<engine>-<profile>-r<revision>
```

Changing the model revision, image digest, topology, engine version, or material launch configuration creates a new recipe ID with an `-r2`, `-r3`, or later revision suffix. Display labels such as **Fast**, **Smart**, and **Long context** are recommendation metadata, not recipe identity.

## Recommendation policy

Recommendations are a generated view, not a second hand-maintained catalog.

A recipe must pass these hard gates before it can be recommended:

- exact hardware and topology match
- `status = validated`
- immutable model revision and container image digest
- runtime adapter supported by Omarchy
- loopback-compatible endpoint contract
- successful real completion on the declared hardware
- current evidence for every advertised capability

The API then ranks the eligible set for an intent. It returns the score components and reason rather than hiding the choice behind one unexplained number. Quality comes from a named evaluation policy, speed and context come from accepted sweep rows, and confidence comes from evidence coverage and recency. Memory requirements come from observed peak usage plus a declared safety margin.

| Intent | Primary ordering |
| --- | --- |
| `balanced` | capability coverage, quality class, decode speed, context, confidence |
| `fast` | warm decode speed, time to first token, footprint |
| `smart` | quality class, capability coverage, measured context |
| `long-context` | measured context, concurrency, then decode speed |

The API returns at most four recommendations by default. Free VRAM and free disk are deliberately excluded from remote ranking because they are current machine state; the CLI applies those gates locally.

## Recipe safety

A recipe is data, but launch data is executable in effect. Omarchy must not run arbitrary commands, scripts, devices, or host paths received from the network.

The first runtime contract supports only a constrained `docker.openai-v1` adapter:

- image pinned by OCI digest
- supported accelerator backend
- tokenized arguments, never a shell command
- allowlisted environment variables
- loopback port publication
- staged registry assets verified by SHA-256
- model caches owned by Omarchy and mounted read-only where possible
- no `--privileged`
- no arbitrary devices or host mounts
- no host networking

Recipes outside that subset can remain visible in the Inference Index, but the recommendation response marks them unsupported by Omarchy. Supporting Compose, controller-owned runtimes, or attributed scripts is a later adapter decision, not something the generic Docker adapter quietly accepts.

## Evidence and promotion

The registry uses four states:

- `candidate`: structurally complete but not launchable by default
- `validated`: immutable and accepted on the declared hardware
- `deprecated`: previously validated, still resolvable, no longer recommended
- `revoked`: known unsafe or incorrect, never launchable

Promotion to `validated` requires:

1. Pinned model revision and image digest.
2. Startup and model identity checks.
3. A non-empty real chat completion.
4. Checks for each advertised capability.
5. At least one declared context and concurrency row.
6. Reproducible evidence tied to the recipe ID, hardware ID, harness version, and date.

A listening port is not acceptance. A benchmark number is not a capability claim. Blank evidence means unmeasured, not zero.

## API surface

The first API is deliberately read-only:

| Request | Purpose |
| --- | --- |
| `GET /v1/hardware/index.json` | List canonical hardware IDs and aliases |
| `GET /v1/hardware/{hardware_id}.json` | Resolve one hardware record |
| `GET /v1/hardware/{hardware_id}/recommendations/{intent}.json` | Return up to four curated choices |
| `GET /v1/recipes/{recipe_id}.json` | Return the exact launch contract |
| `GET /v1/recipes/{recipe_id}/benchmarks.json` | Return protocol-labelled measurements |
| `GET /v1/catalog.json` | Download a compact offline discovery catalog |

There is no submission API in version one. There are also no query parameters: the compiler emits one recommendation file per hardware and intent, and each file contains no more than four entries. A registry change is a Git pull request with schema validation and evidence review. This preserves attribution, review history, and reproducibility without building an administration product.

## Omarchy surface

The user-facing surface can stay small:

```text
omarchy ai list
omarchy ai setup [recipe]
omarchy ai status
omarchy ai start
omarchy ai stop
omarchy ai logs
omarchy ai remove
```

`omarchy ai list` is the single read contract for the menu and bar UI. It combines cached registry data with current local conditions and returns whether each recipe is compatible, runnable now, active, or blocked and why.

Setup should not silently make Local AI the default agent provider when the user already chose another provider. It adds or updates the `local` provider and changes the default only when no default exists or the user asks.

## Delivery plan

### Phase 1: Contract and static API

- Freeze the types in [`INTERFACES.md`](INTERFACES.md).
- Compile the existing Inference Index into static API responses.
- Publish the generated responses on GitHub Pages.
- Return validated recommendations for one RTX 3090 topology and one additional hardware class.
- Add ETag-aware cache and shipped fallback behavior to the CLI.

### Phase 2: Omarchy execution

- Implement the constrained Docker adapter.
- Resolve, inspect, start, stop, and remove one exact recipe.
- Require a real completion before writing agent configuration.
- Keep the endpoint on `127.0.0.1`.

### Phase 3: Recommendation quality

- Add reproducible speed sweeps and capability evidence.
- Generate `fast`, `balanced`, `smart`, and `long-context` views.
- Expand hardware coverage only when a real machine passes acceptance.

### Phase 4: Optional remote access

- Add Tailscale exposure as an explicit post-acceptance action.
- Keep it separate from setup and disabled by default.
- Define authentication and endpoint disclosure before implementation.

## Initial acceptance

The proposal is working when all of the following are true on a fresh supported Omarchy machine:

- hardware detection produces a canonical ID
- recommendations return two to four understandable choices
- the selected response resolves to one immutable recipe
- the CLI can render the exact Docker invocation before running it
- the model starts on loopback and returns a real completion
- the reported model matches the recipe
- the Omarchy agent can use the endpoint
- stop frees the GPU and start reuses cached weights
- offline setup can use the last known-good or shipped catalog
- no remote recipe can introduce an arbitrary host mount or shell command

## Explicit non-goals

- building another model hosting service
- maintaining a mutable registry database
- automatically running unreviewed community recipes
- treating all GPUs with the same VRAM as equivalent
- exposing the endpoint to the LAN or Tailnet during setup
- promising AMD, Intel, or multi-node support before hardware acceptance exists
- ranking models from marketing claims when measured evidence is available
