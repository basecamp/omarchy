# Native Quickshell in sandboxed plugin workers

## Current answer

The installed Quickshell cannot be configured into the required worker mode. Quickshell 0.3.1 statically links its QML modules and native registrations into the `quickshell` executable. Its feature switches disable subsystems at build time; they do not provide a runtime capability profile, an embeddable engine, or a remote surface backend.

Launching the ordinary executable inside Bubblewrap would not solve the integration problem. It would still be designed to create its own native windows and connect directly to compositor and service APIs. Hiding those sockets would make operations fail, but would not translate `PanelWindow`, `Process`, `FileView`, Hyprland, Wayland, or service objects into the authenticated Omarchy plugin protocol. Quickshell's own build documentation also warns that disabling Unix sockets alone does not make arbitrary Quickshell code safe.

The relevant upstream sources are:

- <https://github.com/quickshell-mirror/quickshell/blob/master/BUILD.md>
- <https://github.com/quickshell-mirror/quickshell/blob/master/src/CMakeLists.txt>
- <https://github.com/quickshell-mirror/quickshell/blob/master/src/core/CMakeLists.txt>

## Product decision

The schema-v2 product runtime does not launch or embed a complete Quickshell instance per plugin. It keeps one trusted compositor-facing Quickshell and one deliberately small Qt/QML worker per active sandboxed plugin. Plugin-owned Qt Quick, JavaScript, assets and pure-QML modules remain ordinary presentation code. Calls that previously relied on ambient Quickshell authority migrate explicitly to the worker's `runtime` object.

```text
plugin Qt Quick/QML
    |
    | explicit runtime authority calls
    v
sandboxed plugin worker
    |
    | authenticated frames, damage, input regions,
    | surface declarations, and broker requests
    v
trusted Omarchy Quickshell
    |
    | real PanelWindow, PopupWindow, layer-shell,
    | focus, placement, and compositor policy
    v
compositor
```

The sandboxed worker renders plugin-owned scenes offscreen. The trusted host validates declared surface policy, displays authenticated frames in its own native surfaces, and routes bounded input back to the worker. The worker receives no Wayland, X11, session-bus, shell-IPC, or arbitrary host filesystem connection. This preserves the process-per-principal isolation boundary without paying for a complete Quickshell runtime in every plugin process.

## Possible upstream convergence

The current product does not require a Quickshell fork. A future upstream provider/interface design could allow genuine Quickshell APIs to delegate authority-bearing work to the same restricted runtime contracts. That would reduce plugin migration without changing the broker, grant, revocation, audit, surface-host or sandbox boundaries described here.

### Independently loadable modules

For an embeddable upstream path, Quickshell would need independently loadable, versioned QML libraries instead of making the executable the only container for native registrations and resources. At minimum, core presentation, widgets, window declarations, and I/O interfaces would need to be separable from Wayland, X11, compositor IPC, services, authentication, and capture facilities.

The normal Quickshell executable should consume these same libraries. The plugin worker should load only an exact reviewed module closure. Quickshell uses private Qt APIs, so these libraries and the worker package must remain pinned to and rebuilt for the matching Qt release.

### Embeddable engine

An embeddable upstream engine/runtime API would need to accept explicit module, surface, filesystem, process, socket, environment, screen, and service providers before any plugin QML is loaded rather than requiring the ordinary command-line process and global shell bootstrap.

QML registrations are process-global in important places, so the restricted runtime remains a separate process. The trusted host must never load untrusted plugin QML into its own engine.

### Surface backend abstraction

For genuine source-compatible surface declarations, `PanelWindow`, `PopupWindow`, and related types would need to delegate to a surface backend instead of directly creating compositor-facing windows.

The ordinary backend preserves current native behavior. A remote backend retains the genuine QML types and their property semantics but creates offscreen render scenes. It serializes requested anchors, dimensions, role, visibility, focus, mask, popup relationship, and layer policy through the authenticated worker protocol.

The trusted host treats these values as requests, not authority. Every value is checked against the signed manifest and host policy. Unsupported or excessive requests fail explicitly. The host creates the real window and remains authoritative for screen selection, layer, exclusive zone, keyboard focus, placement, dismissal, and lifetime.

This backend is necessary to preserve source-compatible constructs such as `PanelWindow.anchors`. An `Item` facade cannot reproduce them honestly because `Item.anchors` has incompatible semantics and an Item does not own a native surface.

### Provider-based authority APIs

Authority-bearing Quickshell types could delegate to injected providers rather than call operating-system facilities directly.

| QML API | Ordinary provider | Restricted worker provider |
| --- | --- | --- |
| `Process` | `QProcess` | Manifest-declared broker operation or predeclared sandbox helper |
| `FileView` | Host filesystem | Immutable package assets or brokered private plugin storage |
| Unix sockets | Arbitrary local socket | Pre-created manifest-bound descriptors only |
| `Quickshell.env` | Process environment | Small immutable allowlist of sandbox values |
| Screens | Native screen enumeration | Bounded authenticated host projection |
| MPRIS and services | Session services | Permission-scoped broker models and actions |
| Hyprland and compositor state | Native IPC/protocols | Explicit bounded host projections and gesture-bound actions |

The restricted provider must preserve useful API shape without guessing authority. A command basename must never be heuristically translated into a capability. Executable or broker identity, arguments, limits, cancellation behavior, and required permissions must be declared and bound to the exact plugin revision.

An unavailable provider causes type registration or the attempted operation to fail clearly. It must not silently become a no-op.

### Restricted module profile

An upstream restricted runtime profile would need to register only selected modules and providers. It must not register native Wayland or X11 backends, raw compositor IPC, arbitrary process execution, ambient files, arbitrary sockets, PAM or Polkit agents, session-bus services, capture APIs, or global shortcuts without explicit broker authority.

Compile-time feature flags remain useful for reducing the worker binary, but the security contract must also be explicit and testable at runtime. The worker package should carry a digest of its exact module and provider profile so activation and evidence can bind to it.

### Offscreen rendering and input transport

Each remote Quickshell surface should render through `QQuickRenderControl` into bounded host-provided shared memory or another explicitly negotiated buffer type. The authenticated protocol should carry:

- Frame identity, dimensions, stride, format, sequence, and damage
- Bounded input regions and cursor requests
- Pointer, wheel, touch, keyboard, focus, and input-method events
- Surface lifecycle and visibility requests
- Popup ownership and placement requests
- Bounded tooltip and accessibility metadata

The host validates generation, revision, surface identity, bounds, sequence, and gesture provenance before accepting effects or routing input. Revocation and teardown invalidate the generation before resources are released.

## Security invariants

Native Quickshell compatibility must not change these invariants:

- The trusted host is the only process connected to the compositor for plugin surfaces.
- Plugin QML never executes in the trusted host engine.
- The worker receives no ambient Wayland, X11, D-Bus, shell-IPC, SSH-agent, or host-home access.
- Only exact reviewed QML/native module files are mounted, and plugin-local modules cannot shadow them.
- Steady-state workers cannot create processes or arbitrary sockets.
- Declared helper IPC uses descriptors created before the steady-state filter and cannot inherit host role descriptors.
- Broker operations remain manifest-declared, permission-scoped, generation-bound, revocable, bounded, and audited.
- QML surface declarations cannot widen the signed manifest or host placement policy.
- Unsupported Quickshell APIs fail explicitly instead of silently approximating privileged behavior.

## Product path

1. Continue certifying authority-free standard Qt modules and keep the worker-owned presentation SDK small.
2. Require explicit `runtime` calls for command execution, private state, host observations, external opening, services and surface lifecycle.
3. Port representative plugins and measure changes specifically at those authority boundaries.
4. Keep standard `Quickshell` URIs absent unless a genuine restricted implementation later provides equivalent tested behavior.
5. Offer the provider/interface split upstream as an independent compatibility improvement; do not make completion of the secure runtime depend on it.

A worker-owned facade experiment was removed because it added substantial security and maintenance surface while reducing the representative Radio port by only three production lines. The remote-backend and provider architecture is the path to preserving native Quickshell development with changes concentrated at authority-bearing invocations; until then, the worker exposes only explicitly named Omarchy presentation helpers and certified Qt modules.
