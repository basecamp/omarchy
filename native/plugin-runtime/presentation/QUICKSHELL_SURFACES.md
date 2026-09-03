# Quickshell surface compatibility boundary

The secure worker must not provide source-compatible `PanelWindow` or `PopupWindow` types. Those Quickshell types are native-window contracts, not presentation conveniences. Their behavior includes compositor edge anchoring, layer selection, exclusive zones, popup placement, keyboard-focus negotiation, screen selection, native visibility and close events, and window input masks. The worker owns none of that authority. It renders a `QQuickItem` scene into an authenticated, manifest-bound surface allocated and presented by the trusted host.

An `Item` named `PanelWindow` would be a semantic and security lie. In particular, Qt Quick already owns `Item.anchors`, so the common Quickshell form `anchors { top: true }` cannot be represented by an Item wrapper. Treating `visible`, `screen`, `exclusiveZone`, `WlrLayershell.keyboardFocus`, or `mask` as inert local properties would make code load while silently discarding behavior that developers rely on. Treating multiple child windows below a `ShellRoot` as overlapping items would also collapse separately placed, separately focused surfaces into one manifest surface.

The safe migration boundary is explicit:

- Each externally presented bar, panel, popup, or overlay is a schema-v2 manifest surface whose QML entry root is a `QQuickItem`.
- Host code owns placement, layer, screen, focus policy, exclusive zones, visibility, dismissal, and native window lifetime.
- Plugin code owns only the scene below its allocated render root. The worker resizes that root to the authenticated allocation and transports input only after validating the surface generation and event sequence.
- Dynamic input regions use the bounded `inputRegions` entry-root property and the authenticated input-region transport. A Quickshell `Region` is not accepted as a `PanelWindow.mask` substitute because there is no worker-owned native window to mask.
- Open, close, toggle, and dismiss operations use manifest-bound surface intents. Suspend, resume, and release arrive through the authenticated surface lifecycle; they are not inferred from a local `visible` property or native `closed` signal.

`ShellRoot` may be useful only as an authority-free scope/lifecycle compatibility object. It must not imply that child `PanelWindow` or `PopupWindow` declarations can create surfaces. If provided by the worker compatibility module, its contract must remain explicit about that limitation and it must not enumerate screens, own windows, reload host configuration, or aggregate undeclared surfaces.

`Quickshell.Wayland`, `WlrLayershell`, `WlrLayer`, and `WlrKeyboardFocus` remain unavailable. Providing their enum values or accepting their attached-property assignments would encourage code that appears to request compositor policy even though only the trusted host can do so. A future migration helper may validate legacy declarations against manifest surface metadata, but it must reject mismatches and must not turn plugin-selected values into ambient compositor authority.

This boundary intentionally requires source changes where the source performs native window or compositor work. Presentation below the window remains ordinary Qt Quick/QML and can use the worker-owned compatibility and presentation modules.
