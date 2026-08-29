# Competition winner security-port review

This packet maps the first Omarchy plugin competition winners to the schema-v2 security model. Each port keeps arbitrary plugin-authored Qt Quick rather than replacing it with a declarative component library. Omarchy owns the surface, sandbox, grants, broker, trusted capability definitions, and providers; QML and declared sidecars may communicate freely inside one Bubblewrap sandbox, but host effects require `runtime.invoke` and broker authorization.

The independently installed reference definitions live in `native/plugin-runtime/fixtures/winners/definitions/`. A dynamic manifest request pins the canonical definition name, generation, digest, requested operation subset, and canonical scope. The worker derives the exact definition reference from the parsed manifest, creates a bounded dynamic envelope, and does not accept a QML-supplied definition name, digest, or generation. The broker rechecks the authenticated activation, request, grant, definition, operation, demand scope, gesture, adapter class, adapter ABI, and implementation digest before dispatch.

## Radio Atlas

| Original behavior | Preserved plugin code and UI | Old ambient mechanism | Schema-v2 request and QML call | Denial behavior | Not yet proved |
| --- | --- | --- | --- | --- | --- |
| Rotatable globe, station markers, animation, hit testing, and ranking | Original `Globe.qml` and `RadioModel.js`; custom overlay QML remains unrestricted inside the renderer | Quickshell shell objects and layer-shell window | Host-owned `desktop-overlay` and `bar-embedded` surfaces; no capability required for local rendering | The visual scene still renders | Multiple live surfaces from one worker generation |
| Discover stations | Existing model and selection flow | `Process` launches `curl`; plugin proxy and network namespace | `network.fetch`, generation 1, digest `1b1d34c104f5850ef21c6b16c6d71daa19fe3b7a35f38ab5892d640faf9f5874`, operation `fetch`, scope `GET` plus `https://all.api.radio-browser.info`; `runtime.invoke("fetch", {demandScope, payload})` | No station update; no direct-network fallback | Real bounded HTTPS/Radio Browser adapter, DNS/redirect policy, normalized records, and live network behavior |
| Play and control a station | Player state and controls remain custom QML | Plugin scripts, proxy, `mpv`, sockets, and MPRIS | `media.play-stream`, generation 1, digest `2c0698cd289b084479aa0992cd11ec191b651af0f837e1030aabfed3fdc4e4c9`, operations `play` and `control`, scoped to opaque fetch handles and listed controls | Playback remains stopped; no raw command or socket fallback | Real media provider, opaque-handle handoff, `mpv`/MPRIS lifecycle, and live audio |
| Save favorites and state | Same QML feature | Plugin-selected files through `FileView` | Compiled `storage.private@1`; `runtime.invoke("storage_write", bounded key/value/quota)` | Session behavior continues without durable changes | Rich transactions/list operations and async response integration |
| Auto-dismiss for screensaver | Same optional behavior | Raw Hyprland event stream | `system.observe`, generation 1, digest `dc22d694f498eeb21af02a9e6d0313b20fd2a0e20db5cab64c08630999cfa84c`, operation `observe`, dataset `screensaver.state` | Auto-dismiss is absent | Real sanitized compositor/system observer |

Radio Atlas declares no sidecar. Its old fetch, proxy, and player helpers need host network and media authority, so placing them beside QML would not authorize them; their reusable policy belongs in trusted providers.

## Omagotchi

| Original behavior | Preserved plugin code and UI | Old ambient mechanism | Schema-v2 request and QML call | Denial behavior | Not yet proved |
| --- | --- | --- | --- | --- | --- |
| Pixel-art pet, animation, care, aging, sleep, happiness, pointer interaction, and roaming | Real packaged sprites and arbitrary custom QML run in the worker | Quickshell singleton graph and layer-shell windows | Host-owned bounded `desktop-overlay`; local model work needs no permission | Core pet remains usable | Separate bar/panel/overlay surfaces and cross-monitor handoff |
| Persistence | Pet state and session-only indicator | Direct `FileView` state | Compiled `storage.private@1`; `storage_read` and `storage_write` | Explicit session-only mode; no file fallback | Production async restore/value decoding |
| Care and evolution sounds | Packaged audio cues and care actions | Direct media/process access | Compiled `audio.play-cue@1`, scoped to `eat`, `wash`, `pet`, and `evolve`; `audio_play_cue` | Silent care action | Real packaged-cue playback |
| Evolution notification | Visual evolution remains | Direct notification API | Compiled `notifications.send@1`, category `pet-care`; `notification_send` | Visual evolution continues without notification | Real desktop notification delivery |
| Climb real windows and react to package state | Floor roaming remains | Hyprland/Wayland and package commands | No request; the ambient behavior is removed | Neutral behavior | A trusted sanitized compositor-layout definition and package-state definition |

Omagotchi needs no executable sidecar: model, timers, animation, and sprite selection already share the QML sandbox. The three compiled capabilities intentionally do not carry dynamic definition fields.

## AirPods

| Original behavior | Preserved plugin code and UI | Old ambient mechanism | Schema-v2 request and QML call | Denial behavior | Not yet proved |
| --- | --- | --- | --- | --- | --- |
| Connection, model, pod/case battery, supported controls, listening mode, and settings | Custom pure-QtQuick panel | `FileView` reads daemon status and plugin inherits device identifiers | `device.observe`, generation 1, digest `0813f3e80f26e2c2eed9254c325bca8a6be4980cee94056608cc243590de6c37`, operation `observe`, scoped to a user-selected opaque paired-audio resource and listed fields; `runtime.invoke("observe", {demandScope, payload})` | Disconnected/unknown display; no status-file fallback | Reviewed observer adapter, real daemon integration, and device testing |
| Listening mode, adaptive level, conversation awareness, one-bud ANC, and ear detection | Panel controls and bounded values remain | `Process` launches configurable `librepods-ctl` commands | `device.control`, generation 1, digest `c8449dbd2bfc12dc4f8b18aed658b85e6d461f2efe867f1dca90a63db2541e45`, operation `control`, scoped to the same opaque device and five control names; `runtime.invoke("control", {demandScope, payload})` | Control does not change; no process fallback | Fresh-gesture propagation, reviewed controller adapter, an AirPods device, Bluetooth/AACP, and PipeWire behavior |
| Build/install daemon and user service | Daemon source retained only as provider reference | Plugin setup script compiles and installs privileged host integration | No plugin permission or sidecar | Installation is refused | Separately packaged and reviewed Omarchy provider |

The daemon is intentionally not a same-sandbox sidecar: it needs Bluetooth, PipeWire, D-Bus, pairing state, and host service integration. Those powers belong to a trusted provider, not the plugin sandbox.

## GitHub dashboard

| Original behavior | Preserved plugin code and UI | Old ambient mechanism | Schema-v2 request and QML call | Denial behavior | Not yet proved |
| --- | --- | --- | --- | --- | --- |
| Notifications, reviews, pull requests, issues, actions, and repositories | Custom pure-QtQuick dashboard and sections | `Process` runs `gh`; plugin inherits credentials and network | `remote-account.read`, generation 1, digest `9fbba69a1eefaa3ac03d950e0582b7fd81c1ec468638f04f05225a362f7bbd52`, operation `read`, scoped to `github.com`, a user-selected opaque account, and listed datasets; `runtime.invoke("read", {demandScope, payload})` | Bounded unavailable state; no `gh` fallback | Real account adapter, credential custody, API pagination/rate limits, and live account test |
| Mark notification read | Row action remains | Direct `gh api` mutation | Optional `remote-account.write`, generation 1, digest `f6789af0acdcd56e4ca7266669c1619d494f6f24086502ca9b43a966cf7cffd9`, operation `mark-read`, scoped to the same account and mutation; `runtime.invoke("mark-read", {demandScope, payload})` | Item stays unread | Fresh-gesture propagation and real mutation test |
| Open GitHub item | Open button remains | Direct host URL launch | Optional `external.open-uri.https`, generation 1, digest `8fe8b9861c976f38d1c644b67559e8ce5ba38e8f9ed8c14dfd947fbe77d85398`, operation `open`, origin `https://github.com`, fresh gesture; `runtime.invoke("open", {demandScope, payload})` | Link stays closed | Real host URI provider and browser integration |

`omarchy-github-fetch` is not declared as a sidecar because its purpose is to escape the sandbox through `gh`, credentials, and network. Its service-specific normalization is provider reference material.

## Evidence and limits

All four manifests parse under the current schema. Every migrated QML entry passes `qmllint`. The external-fixture suite loads the real checkout, independently loads and verifies trusted definition documents and adapter registrations, invokes each deterministic test hook, renders a 1280 × 720 software frame through shared memory, and confirms non-transparent pixels for all four ports. Radio Atlas's full original and secure test suite also passes outside the tool sandbox; each other repository's focused secure-port test passes.

The fake adapters prove manifest-to-definition resolution, exact operation binding, QML loading, broker authorization primitives, and visual compatibility. They do not prove a real external effect. Production providers for these winner-specific definitions are deliberately absent. The current QML broker returns asynchronous call objects and opaque response bytes; provider-specific response decoding and complete async UI state handling must be frozen before claiming live behavioral parity. AirPods additionally requires real hardware. GitHub requires a test account. Radio Atlas requires network and audio. Multi-surface product composition remains incomplete.
