# Keeping the two Lab distributions in sync

The native Lab in acrogenesis/omarchy on feature/lab-vm and the standalone acrogenesis/omarchy-lab on main must have the same Lab functionality. A change is not finished until its shared code, fixes, and regression coverage are present and tested in both repositories, and both requested pushes are verified.

Packaging is intentionally different: the native distribution uses omarchy.lab and OMARCHY_PATH; the standalone uses acrogenesis.lab and its private package root, launcher, SSH proxy, and metadata. Do not copy these adapters blindly or change the host's active Omarchy checkout to test them.

## Required release checks

Run the focused Lab suites in the native checkout, its CLI tests, and ./test/all in the standalone checkout. Then compare both actual trees:

```bash
node test/lab-parity.mjs /path/to/native-omarchy /path/to/standalone-lab
```

The checker compares the shared commands, panel, bar, model, and guest assets. It normalizes known path/identity adapters. The exact desktop and SSH packaging adapters are recorded in test/lab-packaging.json; changes to them require deliberate review and adapter-fixture updates in both repos, not broadening exclusions to hide behavior differences. Both distributions include mutation tests for the checker.

When pushing paired changes, push native feature/lab-vm first, then standalone main. Standalone CI also checks parity against the native remote branch. Verify both remote heads and CI. Keep this checker and its packaging fixture identical in both repositories. Update the CI branch reference if native development moves after upstream merge.

For QML changes, verify the actual installed plugin is running current code, not only that files changed or a reload was logged. Same-path QML caching has previously retained an old panel. Restart the actual active shell when required; check its path rather than assuming the systemd environment matches a development shell.

## Installer coverage

First-install tests cover absent/custom repository databases, full-update failure and retry, required hypervisor/SSH packages, safe nested NAT subnet selection, and guest-side display-agent provisioning. Real nested installation must also exercise ISO boot, provisioning, gold/overlay creation, SSH, and viewer startup. Report any end-to-end gaps explicitly.
