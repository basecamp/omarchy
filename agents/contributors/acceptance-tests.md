# Acceptance Tests

Read this before writing or running the graphical acceptance suite under
`test/acceptance.d/`.

The graphical acceptance suite lives in `test/acceptance` with test files under
`test/acceptance.d/*-test.sh`. It exercises a real installed Omarchy desktop,
including session health, shell surfaces, panels, keyboard navigation,
representative applications, and system setup. Source
`test/acceptance.d/base-test.sh` for the shared helpers.

Run acceptance tests in a disposable VM through the sibling `omarchy-iso`
repository, not in the active development session. The suite opens and closes
applications and temporarily changes desktop configuration.

For acceptance-test-only changes, reuse an installed base and sync the suite:

```bash
cd ../omarchy-iso
./bin/omarchy-iso-test release/<iso>.iso --reuse-base --sync-omarchy ../omarchy --no-preview
```

Use `--sync-all ../omarchy` instead of `--sync-omarchy ../omarchy` when the
acceptance run must exercise local `bin/`, `config/`, or `shell/` source too.
Changes to package manifests, installation, finalization, or shipped defaults
require a fresh ISO built from the local checkouts and a run without
`--reuse-base`:

```bash
cd ../omarchy-iso
./bin/omarchy-iso-make --no-boot-offer --local-source ../omarchy ../omarchy-pkgs
./bin/omarchy-iso-test release/<generated-iso>.iso --no-preview
```

Keep unrelated acceptance workflows in separate test files. The runner records
a failed file and continues with the remaining files, which preserves as much
diagnostic coverage as possible. Restore modified user state with traps, close
anything the test opens, and capture every visually distinct state (including
entered input where relevant) as `success-<step>.png`; failure helpers capture
`failure-<step>.png`. The ISO harness collects the screenshots and logs under
its timestamped `test-runs/` directory and opens the screenshots after the run
unless `--no-preview` is passed.

The ISO harness exercises compositor-level shortcuts with QMP virtual keyboard
input. In-guest `wtype` is suitable for typing into focused controls, but it
does not reliably prove that a global Hyprland keybinding works.
