# Local AI registry interfaces

This file is the proposed contract between hardware detection, the read-only registry API, the Omarchy CLI, runtime adapters, and evidence producers. The notation is TypeScript-like for readability; JSON is the wire format.

## Shared primitives

```ts
type SchemaVersion = "omarchy-local-ai/v1"
type HardwareId = string
type ModelId = string
type RecipeId = string
type EvidenceId = string
type IsoDate = string
type Sha256 = `sha256:${string}`
type OciDigestRef = `${string}@sha256:${string}`
type GitCommit = string

type RegistryStatus =
  | "candidate"
  | "validated"
  | "deprecated"
  | "revoked"

type AcceleratorBackend = "nvidia" | "amd-rocm" | "intel-xpu"
type RecommendationIntent = "balanced" | "fast" | "smart" | "long-context"
type Capability = "chat" | "reasoning" | "tools" | "vision" | "structured-output"
type EvidenceResult = "passed" | "failed" | "unsupported" | "unrun"
```

## Hardware

`HardwareRecord` is stable registry data. `LocalHardwareSnapshot` is transient local state and is never required by the normal recommendation API.

```ts
interface HardwareRecord {
  schemaVersion: SchemaVersion
  id: HardwareId
  aliases: string[]
  vendor: "nvidia" | "amd" | "intel"
  product: string
  acceleratorBackend: AcceleratorBackend
  acceleratorCount: number
  memoryBytesEach: number
  topology: {
    kind: "pcie" | "nvlink" | "roce" | "unified-memory" | "other"
    description: string
  }
  platform: {
    os: "linux"
    architecture: "x86_64" | "aarch64"
  }
}

interface LocalHardwareSnapshot {
  hardwareId: HardwareId | null
  detectedAt: string
  accelerators: Array<{
    index: number
    pciId?: string
    totalMemoryBytes: number
    freeMemoryBytes: number
  }>
  freeDiskBytes: number
  docker: {
    installed: boolean
    ready: boolean
  }
  acceleratorRuntime: {
    backend: AcceleratorBackend | null
    ready: boolean
  }
}
```

Example:

```json
{
  "schemaVersion": "omarchy-local-ai/v1",
  "id": "nvidia.rtx-3090.24gb.x1.pcie",
  "aliases": ["rtx-3090", "rtx-3090-24gb"],
  "vendor": "nvidia",
  "product": "NVIDIA GeForce RTX 3090",
  "acceleratorBackend": "nvidia",
  "acceleratorCount": 1,
  "memoryBytesEach": 25769803776,
  "topology": {
    "kind": "pcie",
    "description": "single PCIe GPU"
  },
  "platform": {
    "os": "linux",
    "architecture": "x86_64"
  }
}
```

## Model

The model record describes upstream identity. Weight choice belongs to the recipe because format and revision affect compatibility.

```ts
interface ModelRecord {
  schemaVersion: SchemaVersion
  id: ModelId
  name: string
  family: string
  parameterCount: number
  activeParameterCount?: number
  architecture: "dense" | "moe"
  upstream: {
    repository: string
    license?: string
  }
}
```

## Recommendation

The recommendation response is intentionally small. It is sufficient to render a menu without downloading every recipe.

```ts
interface LocalRecommendationQuery {
  hardwareId: HardwareId
  intent?: RecommendationIntent
  requiredCapabilities?: Capability[]
}

interface RecommendationResponse {
  schemaVersion: SchemaVersion
  hardware: HardwareRecord
  intent: RecommendationIntent
  generatedFrom: GitCommit
  recommendations: Recommendation[]
}

interface Recommendation {
  rank: number
  label: string
  reason: string
  recipeId: RecipeId
  model: {
    id: ModelId
    name: string
    weights: string
  }
  capabilities: Record<Capability, boolean>
  measured: {
    maxContextTokens: number
    maxRequestConcurrency: number
    warmDecodeTokensPerSecond?: number
    timeToFirstTokenMsP50?: number
  }
  requirements: {
    acceleratorCount: number
    minimumFreeMemoryBytesEach: number
    minimumFreeDiskBytes: number
  }
  score: {
    qualityClass: number
    capabilityCoverage: number
    speed: number
    context: number
    confidence: number
  }
}
```

Example response:

```json
{
  "schemaVersion": "omarchy-local-ai/v1",
  "hardware": {
    "schemaVersion": "omarchy-local-ai/v1",
    "id": "nvidia.rtx-3090.24gb.x1.pcie",
    "aliases": ["rtx-3090"],
    "vendor": "nvidia",
    "product": "NVIDIA GeForce RTX 3090",
    "acceleratorBackend": "nvidia",
    "acceleratorCount": 1,
    "memoryBytesEach": 25769803776,
    "topology": {
      "kind": "pcie",
      "description": "single PCIe GPU"
    },
    "platform": {
      "os": "linux",
      "architecture": "x86_64"
    }
  },
  "intent": "balanced",
  "generatedFrom": "179b951612b2e07d447f496269a35def93719646",
  "recommendations": [
    {
      "rank": 1,
      "label": "Balanced",
      "reason": "Validated 128K chat model with the strongest measured balance of capability and speed on one RTX 3090.",
      "recipeId": "gemma-4-12b-it-exl3-4bpw-rtx3090-tabbyapi-tp1-r1",
      "model": {
        "id": "gemma-4-12b-it",
        "name": "Gemma 4 12B IT",
        "weights": "EXL3 4 bpw"
      },
      "capabilities": {
        "chat": true,
        "reasoning": false,
        "tools": false,
        "vision": false,
        "structured-output": false
      },
      "measured": {
        "maxContextTokens": 131072,
        "maxRequestConcurrency": 4,
        "timeToFirstTokenMsP50": 712
      },
      "requirements": {
        "acceleratorCount": 1,
        "minimumFreeMemoryBytesEach": 22548578304,
        "minimumFreeDiskBytes": 12884901888
      },
      "score": {
        "qualityClass": 70,
        "capabilityCoverage": 50,
        "speed": 78,
        "context": 90,
        "confidence": 95
      }
    }
  ]
}
```

The numeric values in this example illustrate the response shape; they are not benchmark claims.

## Recipe

A recipe is the complete, immutable compatibility contract for one hardware topology. Omarchy accepts only recipes whose adapter it explicitly supports.

```ts
interface Recipe {
  schemaVersion: SchemaVersion
  id: RecipeId
  contentSha256: Sha256
  status: RegistryStatus
  description: string

  compatibility: {
    hardwareId: HardwareId
    acceleratorBackend: AcceleratorBackend
    acceleratorCount: number
    minimumMemoryBytesEach: number
    minimumDiskBytes: number
  }

  model: {
    id: ModelId
    repository: string
    revision: GitCommit
    servedName: string
    weightFormat: string
    weightPrecision: string
    downloadBytes?: number
  }

  engine: {
    name: "vllm" | "sglang" | "llama-cpp" | "tabbyapi" | string
    version: string
    graphMode: "full" | "piecewise" | "full-and-piecewise" | "not-applicable"
  }

  launch: DockerOpenAiV1Launch

  endpoint: {
    protocol: "openai/v1"
    containerPort: number
    modelPath: "/v1/models"
    completionPath: "/v1/chat/completions"
  }

  serving: {
    tensorParallel: number
    configuredMaxContextTokens: number
    measuredMaxContextTokens: number
    configuredMaxRunningSequences: number
    measuredMaxRequestConcurrency: number
  }

  capabilities: Record<Capability, boolean>

  validation: {
    acceptedAt: IsoDate
    evidenceId: EvidenceId
    sourceCommit: GitCommit
  }
}
```

## Safe Docker launch contract

The launch contract names an adapter instead of exposing general Docker access. The adapter owns the host paths, security flags, device mapping, container name, restart policy, and loopback publication.

```ts
interface DockerOpenAiV1Launch {
  adapter: "docker.openai-v1"
  image: OciDigestRef
  entrypoint?: string
  arguments: string[]
  environment: Record<string, string>
  sharedMemoryBytes: number
  ipc: "private" | "host"
  assets: RegistryAsset[]
  modelCache: {
    kind: "huggingface" | "http" | "image-bundled"
    repository?: string
    revision?: GitCommit
    containerPath: string
    readOnly: boolean
  }
}

interface RegistryAsset {
  path: string
  sha256: Sha256
  containerPath: string
  mode: "read-only"
}
```

The Omarchy adapter rejects a recipe when:

- the image is not digest-pinned
- the model revision is absent
- an environment key is not on the adapter allowlist
- an asset path escapes the fetched recipe bundle
- an asset checksum does not match
- the recipe requests a shell, arbitrary host path, arbitrary device, privileged mode, host networking, or a non-loopback bind
- the engine or accelerator backend is unsupported locally
- the recipe is not `validated`

## Evidence

Acceptance and performance are separate records. A fast failure is still a failure; a correct completion does not establish a speed claim.

```ts
interface AcceptanceEvidence {
  schemaVersion: SchemaVersion
  id: EvidenceId
  recipeId: RecipeId
  hardwareId: HardwareId
  measuredAt: IsoDate
  harness: {
    repository: string
    commit: GitCommit
  }
  identity: {
    imageDigest: OciDigestRef
    modelRepository: string
    modelRevision: GitCommit
    driverVersion: string
  }
  checks: {
    startup: EvidenceResult
    modelIdentity: EvidenceResult
    chatCompletion: EvidenceResult
    reasoning: EvidenceResult
    tools: EvidenceResult
    vision: EvidenceResult
    structuredOutput: EvidenceResult
  }
  artifactSha256: Sha256[]
}

interface BenchmarkEvidence {
  schemaVersion: SchemaVersion
  id: EvidenceId
  recipeId: RecipeId
  hardwareId: HardwareId
  measuredAt: IsoDate
  protocol: {
    id: string
    revision: GitCommit
    streaming: boolean
    cacheState: "cold" | "warm"
  }
  rows: BenchmarkRow[]
}

interface BenchmarkRow {
  promptTokens: number
  outputTokensRequested: number
  concurrency: number
  samples: number
  status: "accepted" | "rejected" | "infra-invalid"
  prefillTokensPerSecond?: number
  decodeTokensPerSecondAggregate?: number
  decodeTokensPerSecondPerStream?: number
  timeToFirstTokenMsP50?: number
  timeToFirstTokenMsP95?: number
  peakMemoryBytesEach?: number
  peakPowerWattsEach?: number
  peakTemperatureCelsius?: number
}
```

Missing measurements are omitted. They are never encoded as zero.

## Local resolved view

The CLI combines one recommendation with current machine state. This is the JSON contract consumed by the Omarchy menu and bar surface.

```ts
type LocalBlockCode =
  | "unsupported-hardware"
  | "recipe-not-validated"
  | "runtime-not-ready"
  | "insufficient-free-memory"
  | "insufficient-disk"
  | "port-in-use"
  | "unsupported-adapter"
  | "registry-unavailable"

interface LocalRecipeView {
  recipeId: RecipeId
  label: string
  compatible: boolean
  runnableNow: boolean
  active: boolean
  blocks: Array<{
    code: LocalBlockCode
    message: string
    remediation?: string
  }>
  endpoint?: {
    baseUrl: string
    servedName: string
  }
}

interface LocalAiState {
  schemaVersion: SchemaVersion
  hardware: LocalHardwareSnapshot
  registry: {
    source: "network" | "cache" | "shipped"
    commit: GitCommit
    checkedAt: string
  }
  server: {
    state: "not-configured" | "stopped" | "starting" | "ready" | "failed"
    activeRecipeId?: RecipeId
  }
  recipes: LocalRecipeView[]
}
```

## HTTP contract

### List hardware

```http
GET /v1/hardware/index.json
If-None-Match: "registry-commit"
```

```ts
interface HardwareListResponse {
  schemaVersion: SchemaVersion
  generatedFrom: GitCommit
  hardware: HardwareRecord[]
}
```

### Get recommendations

```http
GET /v1/hardware/nvidia.rtx-3090.24gb.x1.pcie/recommendations/balanced.json
```

Returns `RecommendationResponse`.

### Get a recipe

```http
GET /v1/recipes/gemma-4-12b-it-exl3-4bpw-rtx3090-tabbyapi-tp1-r1.json
```

Returns `Recipe`.

### Get benchmarks

```http
GET /v1/recipes/gemma-4-12b-it-exl3-4bpw-rtx3090-tabbyapi-tp1-r1/benchmarks.json
```

```ts
interface BenchmarkListResponse {
  schemaVersion: SchemaVersion
  recipeId: RecipeId
  evidence: BenchmarkEvidence[]
}
```

### Get the offline catalog

```http
GET /v1/catalog.json
```

```ts
interface OfflineCatalog {
  schemaVersion: SchemaVersion
  generatedFrom: GitCommit
  generatedAt: string
  hardware: HardwareRecord[]
  recommendations: Record<HardwareId, Partial<Record<RecommendationIntent, Recommendation[]>>>
  recipes: Array<Pick<Recipe, "id" | "contentSha256" | "status" | "compatibility" | "model" | "engine" | "serving" | "capabilities" | "validation">>
}
```

## Fetch behavior

The initial API is static. It returns `200`, `304`, or `404`; it does not synthesize typed application errors. A known hardware and intent with no validated choices returns a valid `RecommendationResponse` with an empty `recommendations` array. The CLI treats a missing or invalid response as registry unavailability and falls back in order to its last known-good cache and then its shipped catalog.

## Versioning

- The URL major version and `schemaVersion` change only for breaking changes.
- Additive fields may appear within version one; clients ignore unknown fields.
- A recipe never mutates after validation. A material change creates a new recipe ID with a revision suffix.
- Deprecated recipes remain resolvable so installed systems can explain their state.
- Revoked recipes remain resolvable but every client must refuse to start them.
- Every response identifies the Git commit from which it was generated.
