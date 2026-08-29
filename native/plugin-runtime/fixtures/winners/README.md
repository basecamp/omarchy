# Competition winner reference definitions

These package-owned fixtures define the exact dynamic authorities requested by the secure competition-winner ports. They are deliberately outside every plugin checkout: a plugin may pin one of these definitions, but it cannot install or change it.

The adapter digests identify deterministic fake adapters used only by the compatibility suite. A production provider must ship as trusted Omarchy code with its real implementation digest, which necessarily creates a new definition digest and requires plugin review/update before activation.

The existing compiled `storage.private@1`, `notifications.send@1`, and `audio.play-cue@1` capabilities are not duplicated here. They use the bootstrap broker path and therefore do not carry dynamic definition references.
