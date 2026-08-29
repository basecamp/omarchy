# G3 hostile review: E1 embedded bar

## Result

The hostile E1 review found three owning-seam defects and fixed them rather than weakening the vertical proof.

- Worker pointer/touch translation relied on Qt's nullable primary pointing device. Under the offscreen worker this could crash inside `QQuickDeliveryAgent` on authenticated input. Each `WorkerRuntime` now owns fixed-lifetime synthetic mouse and touchscreen devices with host-selected identity, type, capabilities, and point limits. Plugin bytes cannot select either device. Pointer button state is reset on focus loss, suspend, and release. The C5 unit and E1 slice exercise real pointer press/release and touch begin/update/end delivery and finish unfocused.
- `bind_runtime_api(QObject&)` previously accepted any trusted caller-provided QObject, so a future adapter could accidentally expose unrelated invokables or properties to plugin QML. Binding now accepts only a parentless object with no dynamic or declared properties and exactly one public invokable signature: `QVariant invoke(QString,QVariantMap)`. E1 rejects an object that also exposes a host-path method before binding the broker-only adapter. Inherited QObject lifecycle behavior can at most let hostile QML damage its own disposable worker; it conveys no host handle and remains under D5 crash limits.
- Graceful host close discarded its private frame mapping without sending `surface_release`, leaving a surviving worker mapping active until process teardown. D2 now sends the generation-bound surface key before disconnecting, preserves a failed phase if delivery fails, and always clears trusted pixels. D2 and E1 consume that release in the real worker and prove the mapping, focus, render activity, and host image are gone.

The review also strengthened existing claims: D1 identity negatives now cover crossed plugin, revision, and generation; a relative directory import attempting to leave the plugin root fails; audit-before-effect checks the exact broker producer/event/outcome/plugin/revision/generation/correlation/operation; and undeclared `open_uri` is proven not to increment broker dispatch count. E1 still loads and parses the checked-in C10 Pomodoro manifest and QML directly rather than a reduced copy.

## Remaining boundary

E1 is deterministic in-process composition, not installed daemon evidence. Kernel peer credentials and namespace denial remain the transitive D1/B5 tests, while packaging and live compositor placement remain F5. The software-render profile limitations recorded in the E1 handoff are unchanged.

## Evidence

```bash
cmake --build /tmp/omarchy-c5-build -j2 --target omarchy-plugin-worker-runtime-test
ctest --test-dir /tmp/omarchy-c5-build --output-on-failure -R '^plugin-worker-runtime$'

cmake --build /tmp/omarchy-e1-debug -j2
ctest --test-dir /tmp/omarchy-e1-debug --output-on-failure -R 'plugin-embedded-bar-slice|plugin-render-session|plugin-surface-host|plugin-trusted-bridge'
```
