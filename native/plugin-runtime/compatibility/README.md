# Worker Quickshell compatibility

The worker embeds small, versioned, pure-QML compatibility modules under the familiar `Quickshell` and `Quickshell.Widgets` URIs. They are independent implementations; the sandbox never loads the installed Quickshell executable or its native QML registrations.

The initial `1.0` surface contains only authority-free object composition, local visual lazy loading, wall-clock presentation state, icon rendering, and single-child layout wrappers. URLs used by `LazyLoader` and `IconImage` remain subject to the worker source interceptor, so they can resolve plugin-packaged or explicitly certified resources but not network or host filesystem content.

`ShellRoot` is deliberately adapted to the worker's single render scene: it is an `Item`, not a native shell/window owner. `Scope` and `Singleton` retain object grouping and `reloadableId` source compatibility, but the worker has no Quickshell generation-reload lifecycle for them to preserve. QML singleton identity still comes from the standard `pragma Singleton` and `qmldir` declarations. `LazyLoader` covers the common visual-component subset through Qt Quick's `Loader`; native Quickshell's ability to incubate arbitrary nonvisual objects is not claimed. These differences remove host lifecycle authority without silently manufacturing windows or reload persistence.

The following APIs are intentionally absent and therefore fail during QML construction or evaluation instead of becoming misleading no-ops:

- the `Quickshell` singleton, including `env`, `execDetached`, reload, clipboard, screen, window, and working-directory state;
- native windows, layer-shell surfaces, compositor integrations, menus, desktop entries, and ambient services;
- `Variants`, whose common use creates shell-owned windows for ambient screens;
- rounded `ClippingRectangle` and clipping-wrapper types until their rendering semantics can be reproduced without importing Quickshell native registrations or executable resources.

Authority-bearing operations belong in schema-v2 surfaces, broker operations, private storage, packaged-resource adapters, or manifest-declared sandbox helpers. Compatibility APIs must preserve a familiar shape without restoring ambient authority.
