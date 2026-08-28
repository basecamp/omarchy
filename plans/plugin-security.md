# Secure Plugin Model

## Objective

Replace the current all-or-nothing trust model for third-party shell plugins with a capability-based model in which untrusted plugin code runs outside `omarchy-shell`, receives no ambient access to the user's session, and can affect the system only through operations that Omarchy brokers and the user explicitly granted.

The first deliverables are:

1. A repository discussion that establishes the threat model, architectural boundary, permission vocabulary, compatibility policy, and rollout sequence.
2. A focused reference PR that proves the boundary with one useful secure plugin path and adversarial tests, without pretending to migrate the entire plugin ecosystem at once.

The companion [plugin compatibility study](plugin-security-examples.md) maps 20 plugins from a 1,575-source marketplace snapshot to this model at pinned revisions.

## Current state

### Distribution and lifecycle

- A third-party plugin is a Git repository with `manifest.json` at its root.
- `omarchy plugin add` clones into a hidden staging directory under `~/.config/omarchy/plugins/`, validates the manifest, moves the checkout to `~/.config/omarchy/plugins/<id>/`, asks whether to enable it, and tells the running shell to rescan.
- `omarchy plugin update` fetches `origin HEAD`, presents a Git diff unless `--yes` is used, fast-forwards the live checkout, validates the resulting tree, rolls Git back on validation failure, and tells the shell to rescan.
- `omarchy plugin remove` disables the plugin, then deletes a Git checkout, unlinks a symlink, or moves a hand-created directory to a backup.
- Plugins can also be installed or modified directly on disk. An `inotifywait` watcher reloads all plugin panels, services, and widgets after any non-Git change under the user plugin directory.
- The installer does not intentionally run repository hooks or plugin entry points, but installation and update do not yet establish a package authenticity or immutable-revision boundary.

### Discovery and validation

- `shell/services/PluginRegistry.qml` discovers first-party manifests under `$OMARCHY_PATH/shell/plugins/` and third-party manifests one directory below `~/.config/omarchy/plugins/`.
- Manifest schema version 1 requires `id`, `name`, `version`, non-empty `kinds`, and `entryPoints`.
- Supported runtime kinds are `bar`, `bar-widget`, `panel`, `overlay`, `menu`, and `service`.
- The CLI validator checks required fields, entry-point presence, relative entry-point paths, the reserved `omarchy.*` namespace, and symlinks. The runtime repeats only part of those checks.
- The entry-point checks keep the initially loaded file below the plugin source directory. They do not constrain what QML does after it is loaded and therefore are not a sandbox.

### Activation and loading

- Third-party plugins are enabled when referenced by `bar.id`, `bar.layout.*`, or `plugins[]` in `~/.config/omarchy/shell.json`.
- First-party non-bar plugins are enabled by default unless present in `disabledPlugins[]`.
- The shell dynamically creates QML components from manifest entry points with `Loader` or `Qt.createComponent`.
- Service plugins are instantiated at startup when enabled. Panels, overlays, and menus load on demand unless `keepLoaded` is true. Bar widgets are registered as QML components and instantiated inside the active bar. A full `bar` plugin replaces the built-in bar.
- The host injects references including `shell`, `manifest`, `pluginRegistry`, `barWidgetRegistry`, `omarchyPath`, and sometimes a matching service instance. Bar widgets also receive a `bar` object that leads back to the shell.
- All first-party and third-party components share one long-lived `quickshell` process and one QML engine.

### Effective privileges

An enabled schema-v1 third-party plugin has the effective privileges of arbitrary code running as the logged-in user. It can, without declaring or receiving a permission:

- import `Quickshell.Io` and execute arbitrary processes;
- read or write any user-accessible path with `FileView`, a child process, or another available Qt API;
- read the shell environment, including any secrets inherited by the session;
- use the session D-Bus and Quickshell service modules;
- make network requests directly or through child processes;
- access the clipboard and other Wayland facilities exposed to the process;
- create layer-shell surfaces, request keyboard focus, imitate trusted shell UI, or interfere with other shell surfaces;
- inspect and mutate host objects reachable through injected `shell`, `bar`, and registry references;
- register IPC handlers or invoke other plugin and shell methods;
- consume unbounded CPU, memory, processes, and output;
- crash, deadlock, or corrupt the shared shell process, taking the bar, lock UI, notification daemon, and polkit agent down with it.

The current warning and confirmation correctly describe this as unsandboxed code. Disabled-by-default installation, diff review, path validation, namespace reservation, and fast-forward-only updates are valuable safety features, but none is an enforcement boundary once QML is enabled.

### Update race

An enabled managed plugin is updated in its live directory. Git writes trigger the recursive plugin watcher, which can cause the shell to reload new code before post-merge validation completes or before a failed validation rolls the checkout back. Updates need a staged, immutable activation boundary even before the new runtime is complete.

## Threat model

### Protect

- User files, credentials, tokens, agent sessions, keyrings, SSH material, browser data, and environment values.
- Integrity of user configuration and user-owned data.
- User intent for external communication, process execution, clipboard access, URL opening, notifications, and system changes.
- Availability and integrity of the trusted shell, especially lock, authentication, notification, and polkit components.
- Other plugins' state and broker sessions.
- The integrity of installed and activated plugin revisions.

### Adversaries

- A plugin that is malicious when first installed.
- A formerly benign plugin or dependency compromised in an update.
- A plugin that lies about its behavior or requested permissions.
- Malformed plugin output intended to exploit, confuse, exhaust, or spoof the host.
- One installed plugin attempting to impersonate or interfere with another.

### Out of scope for the initial model

- Kernel, Bubblewrap, systemd, compositor, Qt, or trusted Omarchy broker vulnerabilities.
- Protecting data that the user deliberately grants to a plugin from being retained or transmitted through another deliberately granted channel.
- Making arbitrary legacy host-process QML safe. That mode can only be labeled as full user-session access.
- Establishing a complete publisher public-key infrastructure in the first PR. Content identity and origin recording are still required so signing can be added without changing the runtime model.

## Security invariants

1. Third-party code is never evaluated in `omarchy-shell` in secure mode.
2. A secure plugin starts with no home-directory, network, D-Bus, Wayland, device, process-control, or arbitrary command access.
3. Secure third-party QML runs in a separate sandboxed process. It may render arbitrary Qt Quick content, but it does not create objects in the trusted shell engine or directly own privileged compositor surfaces.
4. Every effect outside the plugin's private scratch and state area is a structured broker operation.
5. The broker authenticates the calling plugin from the channel it created; a request cannot choose its own plugin identity.
6. The broker checks every request against the current grant, including resource scope and user-gesture requirements, and denies by default.
7. Manifest declarations are requests, not grants. Omitting a declaration or selecting `--yes` never grants a capability.
8. New or expanded permissions on update are never granted implicitly. The old revision remains active until the new revision and grants are accepted atomically.
9. Installed source is read-only at runtime. Mutable state, cache, and source are separate.
10. Disabling or revoking a plugin terminates its workers, invalidates outstanding broker handles, and takes effect immediately.
11. Broker requests, decisions, revision changes, and grant changes are auditable without logging sensitive payloads.
12. Legacy unsafe mode is visually and semantically honest: it is one indivisible `unsafe.host-code` grant, not a collection of unenforceable granular permissions.

## Target architecture

### Trusted shell host

`omarchy-shell` remains responsible for first-party QML, layout, theming, trusted prompts, surface placement, and security-sensitive input routing. It never evaluates secure third-party QML in its own engine.

Secure plugins use arbitrary-QML remote views. A separate sandboxed QML process renders its scene into a host-consumable buffer or texture. Omarchy embeds that output in a bar slot or presents it through a host-owned panel, popover, slide-out, desktop canvas, or overlay surface, then forwards bounded input and lifecycle events.

The security boundary separates pixels from authority. A remote QML view can use custom controls, layouts, animations, particles, canvases, shaders, and plugin-provided assets. Omarchy retains control of the surface role, monitor placement, dimensions, z-order, exclusive zone, focus policy, input region, frame budget, and relationship to trusted UI.

#### Arbitrary-QML remote views

The QML UI runner should use a dedicated QML engine inside the plugin sandbox and render without creating a native host window. A prototype can use `QQuickRenderControl` with shared-memory frames; a later zero-copy path can use a shared graphics texture if the security and driver tradeoffs are acceptable.

The view protocol needs to carry:

- surface creation and destruction requests constrained by the manifest grant;
- logical and pixel size, device pixel ratio, monitor identity, visibility, and frame scheduling;
- damage or frame updates with hard buffer, dimension, memory, and rate limits;
- pointer, wheel, touch, key, focus, and resize events scoped to the assigned surface;
- theme tokens, reduced-motion state, locale, font scale, and other non-sensitive host presentation state;
- optional accessibility semantics as a side channel, because raw pixels alone are not accessible;
- named effect requests to the broker rather than direct host operations.

Bar widgets receive a host-allocated rectangle but control every pixel inside it. Panels and slide-outs receive a host-owned surface envelope while the plugin controls the complete visual tree within that envelope. Desktop pets and ambient effects can use transparent desktop canvases or movable bounded surfaces with non-rectangular input regions.

#### Surface roles

Surface authority is independently granted from rendering authority. Candidate roles are:

- `bar-embedded`: fixed host slot, no independent Wayland surface;
- `bar-replacement`: host-owned layer-shell bar whose entire visual scene is rendered by one plugin, with bounded exclusive zone and monitor policy;
- `popover` and `panel`: host-positioned transient surface, focus available only after a gesture;
- `slideout`: edge-anchored host surface with bounded anchors and exclusive-zone policy;
- `desktop-overlay`: transparent surface above ordinary windows but below trusted shell prompts and the lock screen;
- `desktop-underlay`: wallpaper-adjacent decoration with no keyboard focus;
- `ordinary-window`: sandboxed XDG toplevel suitable for settings or full applications.

Each role defines maximum surface count, dimensions, monitors, animation/frame rate, input policy, keyboard focus, whether it can cover the screen, and whether it can reserve space. Plugins cannot select trusted layer namespaces, render above authentication or permission prompts, observe global input, or stay active on the lock screen through a general UI grant.

An Omarchy-owned inspection gesture should identify the plugin behind any surface and offer disable, revoke, and terminate actions without relying on the plugin UI. Interactive plugin surfaces should have host-owned identity treatment where spoofing risk warrants it; decorative surfaces should remain visually unconstrained and be identifiable through the inspector.

#### Direct sandboxed windows

Ordinary plugin windows may connect through a per-plugin Wayland security-context socket when the compositor exposes an adequate restricted protocol set. This is simpler and preserves native window behavior, but it is not sufficient for embedding, privileged layer-shell roles, screencopy, input capture, or other compositor-sensitive features.

Do not give the worker the normal session Wayland socket. The security-context identity is useful defense and attribution, but Omarchy must still define the allowed protocol surface and broker privileged operations. Where Hyprland cannot express the necessary per-plugin surface policy, use host-managed remote views rather than weakening the sandbox.

### Plugin supervisor and sandbox runner

Omarchy supervises one QML UI process per active visual plugin and any declared helper workers, with short-lived workers permitted for event-only plugins. All processes for one plugin share a plugin-scoped cgroup and security identity while remaining outside the trusted shell. Each process runs in a Bubblewrap sandbox with:

- a new user, PID, mount, IPC, UTS, and network namespace;
- no Linux capabilities and `no_new_privs`;
- a minimal read-only runtime and read-only bind of exactly one activated plugin revision;
- an empty synthetic home and filtered environment;
- private `/tmp`, `/proc`, and runtime directories;
- no host D-Bus socket, ordinary session Wayland socket, SSH agent, GPG agent, or credential sockets; an `ordinary-window` process may receive only its dedicated security-context Wayland socket;
- a writable private state directory only when `storage.private` is granted, with quotas enforced above the filesystem layer;
- one private broker channel supplied by Omarchy;
- systemd limits for memory, CPU, tasks, restart rate, runtime, and output.

The worker does not gain raw network access when `network` is granted. Network requests remain brokered so host, scheme, method, redirects, response size, and rate can be enforced. The same rule applies to files and external commands: do not mount a broad resource when an operation or opaque handle can be brokered instead.

### Capability broker

The broker is an Omarchy-owned process outside the sandbox, separate from the QML object graph. It owns a distinct authenticated channel for each worker and exposes versioned structured operations. It validates types and bounds before dispatch, checks the active grant on every call, applies rate and concurrency limits, and returns typed results.

The broker should expose domain operations rather than a generic `exec` escape hatch wherever Omarchy can own the integration. Candidate operation families are:

- `storage.private`: quota-bound private key/value or files, never a host path;
- `http.request`: HTTPS requests to granted hosts with bounded methods, redirects, request bodies, response bodies, and rates;
- `files.read` and `files.write`: user-selected documents or directories represented by revocable opaque handles;
- `clipboard.read` and `clipboard.write`, with reads requiring a fresh user gesture;
- `notifications.send`;
- `open-uri`: restricted schemes and optional host scopes, requiring a user gesture;
- `shell.read-theme`, `shell.read-layout`, and narrowly scoped shell events;
- `system.*`: typed Omarchy operations for audio, media, network status, power status, and similar integrations;
- `agent.query` and, separately, `agent.act`, with the agent and broker retaining credentials and enforcing their own approval policy;
- `command.invoke`: an exceptional integration for a user-approved executable and declared operation schemas, not arbitrary shell text.

`command.invoke` is powerful because the invoked host CLI may itself have broad filesystem, credential, and network access. The permission UI must name the executable and operations, and the broker should prefer registered adapters that validate arguments and redact output. A grant to invoke `basecamp notifications list`, for example, must not silently become a grant to run `basecamp auth token` or `bash`.

### Permission store

Grants live in Omarchy-owned state outside plugin source and outside `shell.json`. A grant is bound to:

- canonical plugin id;
- recorded source or publisher identity;
- capability name and API version;
- exact resource scope selected by the user;
- whether the grant is persistent, one-shot, or valid only during a user gesture;
- the revision and requested-capability fingerprint that introduced it;
- grant, denial, and revocation timestamps.

The plugin can inspect whether a requested optional capability is available, but it cannot edit grants. Permission state should be viewable and revocable through both CLI and the Setup menu.

## What changes when an existing plugin becomes secure

An existing plugin cannot be made fully safe merely by adding a permissions array to its current manifest. Its arbitrary QML would still be executing on the trusted side of every proposed check. However, converting a plugin does not necessarily mean discarding all of its code or rewriting its product logic around an unrelated framework.

The transformation is better described as moving the security boundary through the plugin:

| Current schema-v1 plugin | Secure plugin | Migration character |
|--------------------------|---------------|---------------------|
| QML component loaded inside `omarchy-shell` | QML scene loaded in a sandboxed UI process and presented through an Omarchy-owned surface | Architectural packaging change; visual QML can often survive |
| `Process { command: [...] }` or `execDetached()` | Typed broker request such as `command.invoke` | Usually mechanical when an adapter exists |
| `FileView` pointed at a user path | Brokered private storage or a user-selected opaque file handle | Mechanical for private state; product decision for user files |
| Direct HTTP, sockets, or `curl` | `http.request` with granted hosts and bounded responses | Usually mechanical |
| `Qt.openUrlExternally(url)` | `open-uri` request checked against scheme, host, and user gesture | Mechanical |
| Direct clipboard or notification APIs | Brokered clipboard or notification operations | Mechanical |
| `shell`, `bar.shell`, `_services`, registries, or another plugin object | Versioned settings, events, state, and named actions | API migration |
| Arbitrary bar-widget QML | Arbitrary remote QML embedded in a host bar slot | Preserve visual implementation where compatible; replace host-object access |
| Arbitrary panel, slide-out, pet, or overlay QML | Arbitrary remote QML inside a granted host-owned surface envelope | Preserve visual implementation where compatible; migrate surface creation and effects |
| `IpcHandler` registered by the plugin | Plugin-scoped named commands dispatched by the broker | Usually mechanical |
| Pure JavaScript parsing, sorting, validation, reducers, and state machines | The same code inside the worker | Usually reusable unchanged |

The irreducible change is the process and surface boundary, not the visual language. A bar widget cannot remain an arbitrary QML object in the trusted bar engine while also being treated as untrusted, but it can remain an arbitrary QML scene in a separate process and be embedded as a remote view. Import filtering or source scanning is not an enforcement mechanism, and Linux cannot sandbox one QML object inside an otherwise trusted process.

Running the existing QML in a separate sandboxed process preserves ordinary windows immediately and can preserve other plugin kinds through host-managed remote views:

- a service with pure timers and process calls can often move with shims for its external operations;
- a bar widget can render into a host-allocated remote view while keeping its custom QML layout and animation;
- a panel, slide-out, pet, or overlay can render into a host-owned surface envelope while keeping its internal scene;
- an ordinary application or settings window can use a restricted security-context Wayland connection when the compositor policy is adequate;
- surface construction still changes because the plugin cannot directly request arbitrary layer-shell roles, focus, exclusive zones, screencopy, or placement over trusted UI;
- giving the process the ordinary Wayland socket would restore access to every protocol the compositor exposes, so privileged compositor behavior remains brokered or host-owned.

For migration, Omarchy should therefore provide a compatibility SDK and QML bootstrap rather than asking every author to invent a new architecture. The bootstrap supplies remote-view roots for current plugin kinds, theme and sizing state, input/lifecycle events, a `Process`-like broker request wrapper, private state helpers, settings/events channels, named action dispatch, and an accessibility side channel. Authors retain arbitrary Qt Quick content. A converter or lint tool can identify direct imports and generate a migration checklist, but the result still requires author review because permissions, surfaces, and user-visible actions are product decisions.

### Concrete example: authenticated notification plugin

A current Basecamp-style plugin has three intertwined responsibilities:

1. A QML service invokes `basecamp auth status`, lists accounts and notifications, mutates read state, and opens notification URLs.
2. Pure JavaScript parses responses, sorts notifications, filters accounts, and maintains view state.
3. A rich QML bar widget and panel read the service through the host object graph and render the result.

The secure form keeps responsibility 2 substantially intact, moves responsibility 1 to a sandboxed worker using broker requests, and moves responsibility 3 into a sandboxed remote QML view.

Illustrative sandboxed controller code:

```javascript
const accounts = await api.command.invoke("basecamp.accounts.list", {})
const notifications = await api.command.invoke("basecamp.notifications.list", {
  accountIds: accounts.map(account => account.id),
  limit: settings.maxPerAccount
})

model.replaceAccounts(accounts)
model.replaceNotifications(notifications)
```

The existing QML binds to `model` inside the sandboxed engine and renders through the granted `bar-embedded` and `panel` remote surfaces. Its click handlers call named controller methods, which in turn use the broker. It no longer publishes a host component description or reaches into the host object graph.

Illustrative requested operations:

```json
{
  "permissions": {
    "required": [
      {
        "capability": "command.invoke",
        "adapter": "basecamp",
        "operations": [
          "auth.status",
          "accounts.list",
          "notifications.list",
          "notifications.read"
        ],
        "reason": "Read and update Basecamp notifications using your existing Basecamp CLI login"
      },
      {
        "capability": "open-uri",
        "schemes": ["https"],
        "hosts": ["*.basecamp.com"],
        "userGesture": true,
        "reason": "Open a notification selected in the panel"
      }
    ]
  }
}
```

This is a meaningful authority and packaging transformation, but not a wholesale product or visual rewrite. The parsing/model tests, business rules, and much of the QML scene can survive; direct host-object access, surface creation, and ambient effects do not. The reference implementation should include a before/after sample and a measured migration inventory so the discussion can evaluate actual author cost instead of comparing abstractions.

### Findings from representative plugins

The ecosystem study identifies four migration lanes rather than one universal rewrite:

1. Local visual plugins such as a Pomodoro timer can usually retain their QML scene, state machine, and model while replacing their root surface and ambient effects.
2. Authenticated services such as Basecamp need a registered broker adapter, but can preserve response parsing and most domain behavior.
3. Desktop integrations such as TOTP scanning, OCR, browser routing, Docker control, proxy control, media playback, and workspace overviews need purpose-built broker APIs or trusted portals. Granting raw commands, D-Bus, Wayland, Docker sockets, or compositor IPC would undo the security boundary.
4. Plugin managers and complete shell suites can cross into host-extension territory because they control lifecycle or require nearly every surface and system capability. A full visual bar replacement alone can remain secure as a host-owned `bar-replacement` surface rendered by sandboxed QML.

The examples also expand the minimum platform surface beyond a generic process shim. A viable migration path needs private storage, notifications, named sounds, scoped HTTP including explicit loopback scopes, credential handles, file handles, clipboard write, gesture-scoped selection read, focused-input insertion with preview, media and device adapters, update workflows, sanitized shell events, named compositor actions, and trusted capture/default-handler portals. The API should be introduced in reviewed groups; the first PR must continue to deny the groups it has not implemented.

Permissions must be evaluated in combination. Clipboard or screencopy plus network, credentials plus an output channel, and URL-handler registration plus application launch are materially more dangerous than their individual descriptions suggest. Where possible the broker should compose the operation without exposing the sensitive value to the worker.

### Compatibility behaviors to preserve deliberately

Security design should preserve the product outcome of these current behaviors unless the discussion explicitly decides otherwise:

- **Arbitrary visual composition:** custom QML controls, animations, shaders, transparent surfaces, slide-outs, pets, ambient effects, and unusual layouts remain possible through remote QML views.
- **QML interaction fidelity:** nested components, loaders, local assets and fonts, popups, tooltips, cursor shapes, drag and drop, text selection, IME, accessibility, dynamic sizing, device-pixel-ratio changes, and multi-monitor behavior need explicit compatibility tests. Remote pixels alone preserve appearance but not all of these semantics.
- **Surface variety:** bar widgets, panels, overlays, menus, full bars, desktop decorations, and ordinary windows need clear secure surface roles. A complete shell replacement may still become a host-extension trust class when it requires trusted prompts, lifecycle authority, or unrestricted cross-surface control.
- **External invocation:** keybindings, shell commands, desktop entries, and other applications can summon a plugin through authenticated, plugin-scoped named commands without exposing arbitrary IPC registration.
- **Background autonomy:** services can subscribe to granted events, use timers, refresh while their UI is closed, and raise bounded notifications. Requiring a gesture for every background read would break status and automation plugins, so each capability must distinguish background observation from gesture-bound disclosure or mutation.
- **Fast local development:** authors need an explicit developer runtime with hot reload, diagnostics, QML inspector support, and local source mounts. It can be clearly unsafe or use the same sandbox with mutable source, but normal managed plugins should remain immutable.
- **Composition:** plugins currently share services and reach through the shell object graph. Secure replacements need typed service publication, event topics, and explicit plugin-to-plugin dependencies instead of eliminating composition entirely.
- **Native and command-line helpers:** plugins can retain bundled workers and existing CLIs inside the sandbox or behind reviewed adapters. The lifecycle must define architecture compatibility, executable provenance, resource limits, dependency discovery, and upgrades without running arbitrary host installers.
- **User-owned data:** some plugin files are intentionally portable, editable, or consumed by other tools. Private storage cannot replace those semantics; persistent user-selected handles and explicit import/export are required.
- **Install and removal cleanup:** plugins that create desktop handlers, user services, credentials, or integrations need broker-owned transactional setup and teardown with recovery. Silently abandoning lifecycle hooks would leave unsafe residue even if runtime execution is contained.
- **Offline and local-first operation:** the broker cannot require cloud services or route local computation through a remote service. Local OCR, model inference, parsing, timers, and device integrations remain first-class.
- **Whole-shell experimentation:** users can still install arbitrary in-process QML as an explicitly trusted host extension. The model must not call this granularly sandboxed, but it should remain a supported power-user workflow rather than an accidental loophole.

These behaviors should become compatibility requirements and acceptance scenarios. The security model may change how they are implemented, but should not remove them by default merely because the first reference slice is smaller.

## Permission vocabulary

Permissions should be structured requests with a human explanation, not broad strings whose consequences differ by implementation. A schema-v2 sketch:

```json
{
  "schemaVersion": 2,
  "id": "org.example.status",
  "name": "Example Status",
  "version": "2.0.0",
  "runtime": {
    "apiVersion": 1,
    "qml": "ui/Status.qml",
    "worker": ["worker/example-status"]
  },
  "surfaces": {
    "barWidget": {
      "role": "bar-embedded",
      "defaultSection": "right"
    }
  },
  "permissions": {
    "required": [
      {
        "capability": "http.request",
        "hosts": ["status.example.com"],
        "methods": ["GET"],
        "reason": "Fetch the service status shown in the bar"
      }
    ],
    "optional": [
      {
        "capability": "notifications.send",
        "reason": "Notify when the service becomes unavailable"
      }
    ]
  }
}
```

The final schema should use a registry of capability definitions maintained by Omarchy. Each definition owns validation, risk text, whether its scope can be narrowed by the user, whether it requires a user gesture, and which broker operation implements it.

Do not add a generic `network`, `filesystem`, `session-bus`, `wayland`, or `process` permission to secure mode. Those restore ambient authority and make per-action broker checks impossible.

## Install, enable, update, and revoke flows

### Install

1. Fetch into a network-constrained staging environment without executing plugin code, repository hooks, dependencies, or build scripts.
2. Validate the complete schema and tree, reject special files and symlinks, canonicalize every path, and enforce size and file-count limits.
3. Record origin, resolved commit, tree digest, manifest digest, and requested-capability fingerprint.
4. Present required and optional permissions before activation. The user explicitly selects optional permissions and any resource scopes.
5. Copy the validated tree into a content-addressed, read-only revision store.
6. Record the grant separately.
7. Enable only if every required permission is granted. Otherwise keep the plugin installed and disabled with a clear explanation.

`--yes` may accept an install or code revision, but it must never mean “grant everything.” Non-interactive callers use explicit `--grant` arguments or a reviewed policy file. Missing required grants fail closed.

### Enable

Before starting a worker, revalidate the activated revision identity and required grants. Starting the worker and accepting its first validated surface and frame should be one supervised transition. A failed or crashing worker cannot affect trusted shell components.

### Update

1. Fetch into a new staging revision while the active revision remains immutable and running.
2. Validate the staged tree before any code can run.
3. Show the code/revision change and a separate permission diff.
4. Preserve grants only for identical or narrower capability requests. Require explicit selection for additions or expanded scopes.
5. Start and health-check the new revision in its sandbox.
6. Atomically switch the active revision and grant fingerprint, then stop the old worker.
7. On any failure, keep the old revision and grants active. Never write new code into a live plugin directory.

The default interactive updater may continue to ask for every revision, matching today's diff-review behavior. An unattended updater may accept a revision with an unchanged permission fingerprint only under an explicit user policy; it still cannot grant new permissions.

### Revoke and remove

Revocation stops the worker or cancels only the affected operation, depending on the capability, and invalidates handles immediately. Removal stops the worker before detaching its activated revision, deletes grants and private broker state only after a separate state-retention choice, and keeps audit records according to a bounded retention policy.

## Authenticity and supply chain

Sandboxing limits impact but does not answer who published a plugin or whether an update is expected. The lifecycle should establish these layers independently:

- record and display the exact origin and commit for every installed revision;
- store and activate content by digest;
- reject origin changes as an identity change;
- support pinned versions and easy rollback;
- treat Git commit or tag signatures as additional evidence, not universal identity;
- let a future official registry publish signed source-to-id and revision attestations, review status, revocations, and reproducible artifact digests;
- never execute install, update, dependency, or build hooks on the host.

A curated or reviewed marketplace entry is not a substitute for the runtime sandbox, and an effective sandbox is not a substitute for publisher identity.

## Compatibility policy

Schema-v1 arbitrary QML cannot receive enforceable granular permissions because it executes inside the trusted process and can import the underlying APIs directly. There are only honest choices:

1. Continue loading it with a single explicit `unsafe.host-code` grant that means full user-session access.
2. Refuse to load it.

Recommended rollout:

- Keep first-party packaged QML trusted and in-process.
- Label every third-party schema-v1 plugin as legacy/full access in list and menu output.
- Require an explicit unsafe grant for new schema-v1 installations immediately; do not let `--yes` imply it.
- Preserve existing enabled installations for one transition release only after showing a migration notice, then require confirmation or disable them.
- Disable automatic hot reload for managed legacy plugins. Keep an explicit developer mode for local authoring.
- Provide a schema-v2 SDK and migration examples before making secure mode the only default.
- Treat clones of first-party QML as developer code: they also require the unsafe grant until converted to the sandboxed QML runtime.

## Immediate hardening for schema v1

These changes reduce current exposure but must not be marketed as a sandbox:

- Stage and validate updates outside the live plugin directory, then switch revisions atomically.
- Stop reloading managed plugins on arbitrary writes. Watch only an explicit development directory or developer-mode plugin.
- Make runtime validation at least as strict as install validation, including supported kinds, required entry points, canonical paths, file existence, special files, and symlinks.
- Keep managed revisions read-only and separate caches/state from source.
- Record origin, commit, and content digest; show them in `omarchy plugin list --json` and update prompts.
- Unload an enabled legacy plugin before switching its active revision.
- Add size, file-count, output, and update time limits.
- Remove direct host-object injection where first-party components do not require it. This is defense in depth, not a boundary for legacy third-party QML.

## Reference implementation PR

The reference PR should prove that arbitrary QML can remain expressive across the process boundary while its system authority and surface role are enforced independently.

### Proposed vertical slice

- Add a schema-v2 manifest validator for one remote-QML `bar-widget` surface and a QML entry point.
- Add a sandboxed QML UI runner using `QQuickRenderControl`, initially rendering bounded shared-memory frames without a Wayland connection.
- Add an Omarchy-owned remote-view host that embeds the plugin frames in a bar slot and forwards bounded pointer, keyboard, focus, resize, lifecycle, theme, and device-pixel-ratio events.
- Add a plugin supervisor/runner that starts a worker in Bubblewrap with no home, network, D-Bus, Wayland, or inherited environment and with read-only source plus private temporary directories.
- Add a minimal broker with authenticated per-worker channels and four operations: `storage.private`, `notifications.send`, `audio.play-cue`, and a fake registered service adapter with enumerated operations. The sample plugins request the optional effects and the adapter independently.
- Add a grant store and CLI verbs to inspect, grant, and revoke permissions.
- Change add/enable/update paths for schema v2 so required grants are explicit and updates are staged before activation.
- Ship a Pomodoro-style fixture with custom QML animation that proves remote rendering, timer state, private persistence, named actions, optional sound, and notifications.
- Ship a transparent animated pet or slide-out fixture that proves freeform QML, alpha, animation, bounded surface roles, input regions, and the host-owned inspection/termination path.
- Ship a Basecamp-style fixture backed by fake data that proves enumerated authenticated-service operations, a custom QML list, a user-gesture URL action, denial of undeclared operations, and permission diffs without requiring a real account.
- Add a report-only migration inventory that detects high-signal QML imports, ambient APIs, executable prefixes, path roots, URL hosts, shell object injection, and host-integration files, then produces an author-reviewed worksheet.
- Keep schema-v1 loading behavior behind an explicit legacy path in this PR; do not claim that it is sandboxed.

### Proof tests

Automated tests must demonstrate successful behavior and failed attacks:

- a plugin can render arbitrary QML into an embedded bar slot, animate within its frame budget, receive forwarded input, and invoke a declared named action;
- a transparent pet or slide-out remains confined to its granted surface role, dimensions, monitor, input region, focus policy, z-order, and frame rate;
- a plugin cannot see the real home, plugin source is read-only, and unrelated plugin state is absent;
- direct IPv4, IPv6, Unix sockets other than assigned render/broker channels, session D-Bus, the ordinary session Wayland socket, and inherited agent sockets are unavailable; an `ordinary-window` fixture sees only the globals exposed through its dedicated security-context connection;
- the broker denies an undeclared operation, an ungranted optional operation, an expanded resource scope, a forged plugin id, malformed messages, oversized messages, excessive rates, and stale handles;
- `--yes` does not grant permissions;
- an update requesting a new permission remains staged and the old revision keeps running;
- a failed health check, malformed frame, oversized buffer, invalid surface request, or broken UI process leaves the trusted shell and old revision intact;
- revocation terminates or immediately blocks the affected capability;
- worker crash loops, output floods, and memory/process exhaustion are bounded without restarting `omarchy-shell`;
- a malicious schema-v1 fixture cannot be presented as granularly sandboxed and requires the unsafe grant.

Run focused CLI and shell suites plus a disposable-VM acceptance test that interacts with the rendered widget. Because the new renderer has a visual effect, verify it in the running UI following `agents/skills/visual-verification.md` before opening the PR.

## Rollout sequence

1. Publish the discussion and settle the threat model, remote-QML boundary, surface roles, legacy policy, permission vocabulary, and first vertical slice.
2. Land immediate schema-v1 update and validation hardening if it can be reviewed independently.
3. Land the reference schema-v2 QML runner, remote-view host, broker, grants, sample fixtures, and adversarial tests.
4. Expand surface roles and broker operations based on real migrations, preferably one local-status plugin, one freeform overlay, and one authenticated service such as Basecamp.
5. Add permission management UI, audit inspection, resource pickers, and marketplace metadata.
6. Deprecate new unsafe schema-v1 installation by default, then require an explicit developer switch after the ecosystem has a viable v2 SDK.
7. Add signed registry metadata, revocations, and review attestations without weakening local origin and digest checks.

## Decisions needed in the discussion

- Which remote-rendering transport should the first implementation use, and what evidence is required before moving from shared memory to a zero-copy graphics path?
- Does the first QML runner use software rendering, restricted GPU render-node access, or both, and how is the additional driver/kernel attack surface represented?
- Which surface roles belong in API version 1, and which focus, z-order, size, input, and lock-screen restrictions are fixed invariants rather than user-grantable permissions?
- Which current Quickshell types receive compatibility shims, which remain available but confined inside the sandbox, and which fail explicitly because they imply compositor or host authority?
- What side-channel protocol is sufficient for accessibility, IME, drag and drop, popups, cursor state, and other behavior that cannot be reconstructed from rendered frames alone?
- Should existing enabled schema-v1 plugins be grandfathered for one release, disabled immediately, or left enabled until their next update?
- Is `unsafe.host-code` available in normal settings, only through CLI, or only after enabling developer mode?
- Which real plugin should be the compatibility target for the first panel or overlay surface role?
- At what point does a multi-surface plugin become a trusted shell extension rather than a secure plugin with many explicit grants?
- Should every code update require confirmation, or may users opt into unattended updates when the permission fingerprint is unchanged?
- Which implementation language and process owns the broker, and how is it packaged and supervised?
- Which capability families are stable enough for API version 1, and which remain experimental?
- What publisher identity and marketplace attestation model should follow the runtime boundary?

## Success criteria

The model is successful when a malicious or compromised secure plugin can do no more than consume bounded resources, render within its assigned untrusted UI region, use the exact broker operations and scopes the user granted, and damage or disclose only data already entrusted to those operations. It must not be able to read arbitrary home files, reach the network or session bus directly, execute arbitrary host commands, impersonate trusted authentication UI, interfere with another plugin, or take down `omarchy-shell` merely by crashing its own worker.
