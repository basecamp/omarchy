# E0 headless vertical slice

E0 composes the production C7/D1 launch and authenticated-channel boundary with the D5 health supervisor. It deliberately adds no plugin-facing authority: the downstream dispatcher receives already-authenticated packets but has no filesystem, process, compositor, network, or desktop-service handles of its own.

The slice rejects any launch request whose plugin, immutable revision, or generation differs from the B2 activation binding. A trusted live-generation authority is required by D1 before launch, after negotiation, and before dispatch. D5 adopts the same exact binding before readiness, meters every broker packet by correlation and byte count, observes resource samples, writes redacted lifecycle audit records, and owns bounded termination.

The focused test proves rejection before launch for a mismatched binding, aggregate three-role negotiation, one authenticated broker request through the health admission/completion gate, zero UI surfaces, an accepted resource sample, durable authority-free lifecycle audit records, and clean worker/resource-scope teardown. The same test target runs through the fake launcher and the real Bubblewrap launcher; the C11 sandbox certificate independently exercises denial of the real home, session bus, Wayland socket, network, excess descriptors, and descendants using the identical C7 plan.
