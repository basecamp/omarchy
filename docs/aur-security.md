# Hardened AUR consumption

Omarchy treats AUR recipes as untrusted executable code. A PKGBUILD review is useful evidence, but it is not a sandbox, an attestation, or proof that a package is safe.

The long-term design goal is a hash-bound pipeline that links an exact AUR commit to verified sources, a disposable build environment, the inspected package artifact, a policy verdict, and the final pacman transaction. The supported path must fail closed when any required link is missing.

## Emergency review gate

The current first slice removes unattended trust while the isolated build and attestation pipeline is being developed:

- `omarchy-pkg-aur-add` requires an interactive terminal for missing packages and opens the complete recipes and available Yay/Git diffs in Omarchy's blocking terminal viewer. It requires pacman's final confirmation and separates package names from options without launching the user's potentially detached GUI editor.
- `omarchy-pkg-aur-install` routes its selections through `omarchy-pkg-aur-add` and does not keep sudo credentials alive while untrusted build code runs.
- `omarchy-update-aur-pkgs` performs a read-only available-version query first. Interactive updates use the same full-recipe, diff, and confirmation policy. `omarchy update -y` and other non-terminal runs report and hold AUR updates instead of installing them, even though the update logger itself runs inside a pseudo-terminal.
- A pending ordered migration that cannot start interactive AUR review returns the migration deferral status. The migrator leaves it pending and stops later migrations, while allowing the surrounding system update to finish. Build and transaction failures retain their real status and fail the migration.
- A failed optional update query is reported and AUR changes are held, while the trusted system update continues. A declined or broken optional AUR update is handled the same way; a directly requested AUR install still propagates failure.

This gate deliberately does not claim to make AUR packages safe. After approval, yay still sources and executes PKGBUILDs as the user, fetched sources are not yet bound to an Omarchy verdict, build code is not isolated from the host, and the resulting artifact is not independently inspected or attested. Users can also bypass the supported path by invoking Arch packaging tools directly.

## Next trust boundaries

Implementation should deepen the boundary in this order:

1. Resolve each package base and dependency to an immutable AUR Git commit, retain the reviewed tree, and produce a deterministic recipe/source/history report without sourcing PKGBUILDs on the host.
2. Fetch and verify declared sources separately, recording final origins and content hashes.
3. Build in a disposable VM or another explicitly documented security boundary with no user secrets or host home and with network denied after source acquisition.
4. Inspect the final Arch package for sensitive paths, scriptlets, hooks, services, privilege mechanisms, metadata mismatches, and ownership conflicts.
5. Bind recipe, sources, builder, artifact, findings, policy, and human approvals in a signed attestation accepted by a narrow installation gate.
6. Add hash-keyed quarantine, cooldowns, last-known-good artifacts, signed shared intelligence, and optional remote builders without making remote availability part of the local verification root.

Strict mode must not silently degrade when acquisition, scanning, isolation, artifact inspection, signature verification, or quarantine checks fail. Compatibility exceptions must be human-granted, expire, and apply to one immutable recipe or artifact hash rather than a package name.
