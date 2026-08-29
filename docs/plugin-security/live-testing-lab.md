# Plugin security live-testing lab

This lab runs schema-v2 beside an existing Omarchy 4.x installation. It does not replace `/usr/share/omarchy`, alter `~/.config/omarchy`, discover schema-v1 plugins, enable `omarchy-plugin-host.service`, or install an `omarchy-dev` package. The only system path is one new digest-named directory below `/opt/omarchy-plugin-security-lab/`. Use a disposable account or VM even with that separation: the live-lab broker deliberately performs real granted effects.

## Build and stage

Record a clean source identity, configure a Release build, and run its focused tests outside development sandboxes that block user namespaces or `SO_PASSCRED`:

```bash
git status --short --branch
git rev-parse HEAD
cmake -S native/plugin-runtime -B /tmp/omarchy-plugin-runtime-live-lab -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/omarchy-plugin-runtime-live-lab
ctest --test-dir /tmp/omarchy-plugin-runtime-live-lab --output-on-failure -L security
ctest --test-dir /tmp/omarchy-plugin-runtime-live-lab --output-on-failure -R '^plugin-sidecar-(supervisor|real-bwrap)$'
native/plugin-runtime/lab/omarchy-plugin-security-lab prepare /tmp/omarchy-plugin-runtime-live-lab /tmp/omarchy-plugin-security-stage
```

`prepare` never writes `/opt`. It installs into a new user-owned staging directory named by the SHA-256 of `ARTIFACTS.sha256`, a deterministic manifest containing the mode, content digest, and relative path of every installed runtime artifact, including `PROVENANCE`. `PROVENANCE` records the source commit, dirty-tree fingerprint, independently pinned worker and host digests, CMake cache digest, and host Omarchy version. A host-only, worker-only, bridge, library, tool, or provenance change therefore creates a different bundle root. A dirty-tree fingerprint is evidence, not a substitute for a clean commit.

Review the complete staged file list and provenance before copying it:

```bash
stage=/tmp/omarchy-plugin-security-stage/<bundle-sha256>
find "$stage" -printf '%M %u:%g %p\n' | sort
cat "$stage/ARTIFACTS.sha256"
cat "$stage/PROVENANCE"
native/plugin-runtime/lab/omarchy-plugin-security-lab verify "$stage"
```

Then create a new root-owned path without overwriting an existing candidate:

```bash
digest=$(basename "$stage")
lab_root=/opt/omarchy-plugin-security-lab/$digest
sudo test ! -e "$lab_root"
sudo install -d -o root -g root -m 0755 /opt/omarchy-plugin-security-lab
sudo cp -a --no-preserve=ownership "$stage" "$lab_root"
sudo chown -R root:root "$lab_root"
sudo chmod -R go-w "$lab_root"
sudo chmod 0755 "$lab_root"
native/plugin-runtime/lab/omarchy-plugin-security-lab verify "$lab_root"
```

The helper verifies the manifest identity and regenerates it from the staged tree before every launch, rejecting added, removed, renamed, mode-changed, or content-changed artifacts. The live-lab launcher independently requires the worker at `/opt/omarchy-plugin-security-lab/<bundle-sha256>/usr/lib/omarchy/plugin-runtime/omarchy-plugin-qml-worker` and receives both the bundle digest and the worker digest. It rejects symlinks, non-root ownership, group/world-writable path components, unsafe executable metadata, a noncanonical bundle location, and a worker digest mismatch. Production launch continues to pin `/usr/lib/omarchy/plugin-runtime/omarchy-plugin-qml-worker`; normal preview cannot select the lab worker.

## Isolated test state

Use copies of the schema-v2 ports, never their schema-v1 installed directories. Keep each revision immutable during a run and keep all mutable authority outside it:

```text
/tmp/omarchy-plugin-lab-run/<run-id>/
  plugins/<plugin-id>/       immutable reviewed source copy
  grants/                    permission store
  state/<plugin-id>/         plugin-private state
  audit/                     broker audit store
  evidence/                  screenshots, video, logs, hashes
```

Use `omarchy-plugin-host --identify-plugin-live-lab` to record the plugin tree and request digests. Review grants interactively with `omarchy-plugin-permission-store`; do not construct granted store bytes by hand. Activate only the exact reviewed candidate using `--activate-plugin-live-lab`. The feature flags enable these explicit commands only; they do not discover or start plugins automatically.

Launch one reviewed plugin with:

```bash
native/plugin-runtime/lab/omarchy-plugin-security-lab launch "$lab_root" "$plugin_root" "$tree_sha256" "$grant_store" "$private_state" "$audit_store"
```

Run Radio Atlas with live network and media providers, Omagotchi with private storage, notifications and packaged audio, GitHub with a disposable test account, and AirPods only with test hardware whose pairing can be reset. Capture the initial surface, each granted operation, each denied operation, revocation during an in-flight request, provider loss, plugin crash, worker restart, and post-revocation behavior. Record `hyprctl` state and use compositor-native capture for video; export the redacted audit store and hash every evidence file.

For a deterministic first proof that does not modify a winner port, use the purpose-built fixtures under `native/plugin-runtime/fixtures/product/`. `lab-authorized` invokes `storage.private/write` and then `storage.private/read` on startup and renders the completed broker round trip. `lab-denied` invokes `notifications.send/send` without requesting it and renders the broker denial. `lab-permission` requests notification authority only as optional UI state and updates its visible status from the host-authenticated `permissionsChanged` snapshot; it never treats that snapshot as authorization. The live-lab host polls its isolated grant store and accepts only one exact active grant transition from granted to revoked at the next epoch; it applies the broker/provider revocation before sending the reduced availability snapshot and exits fail-closed for expansion, replacement, replay, restart-required revocation, or binding drift. Run each fixture from an immutable copy with a fresh mode-0700 state, grant, audit, and evidence directory. Correlate the visible terminal state with the private-state bytes and audit decisions rather than treating a screenshot alone as proof.

## Omagotchi persistence proof

The live private-storage backend does not add an on-disk envelope. A storage key is the exact regular-file name below the plugin's mode-0700 private-state directory, and a write atomically replaces that file with the exact value bytes supplied by the authorized request. For Omagotchi, seed `pet-state` as a mode-0600 regular file containing compact UTF-8 JSON that fits the granted 4096-byte item limit. Do not add a newline, symlink, hard link, temporary `.omarchy-tmp-*` name, or handcrafted broker response. Record the seed bytes and SHA-256 before launch.

The broker result returned to QML is distinct from that raw file representation: `storage.private/read` returns one found byte, three reserved zero bytes, a big-endian 32-bit value length, then the exact stored bytes. A persistence-capable Omagotchi port or purpose-built QML fixture must decode that result, reject malformed length or reserved fields and invalid JSON, apply bounded typed fields, and visibly render a deterministic marker from the restored state. The current reviewed Omagotchi port only records whether the read call was allowed and does not consume `call.value`, so a screenshot of that revision cannot prove restoration even when the audit records a successful read. Correct that port or use a reviewed persistence fixture before claiming winner parity.

Run the next persistence campaign as one immutable sequence:

1. Create a fresh mode-0700 state root and atomically install a reviewed `pet-state` seed with distinctive bounded values, such as generation 7 and hunger 61. Hash the file, immutable plugin tree, grant store and runtime bundle.
2. Launch through the root-pinned live lab. Require a successful audited `storage.private/read` and a visible `RESTORED 7 / 61` marker derived from decoded bytes, not fixture constants.
3. Invoke a fixture-owned startup hook that performs one deterministic model transition and calls the ordinary `runtime.invoke("storage_write", ...)` path. This hook may be timer-driven or selected by immutable fixture content; it must not write the state directory directly and must not require a GUI actuator. Require the authorized write request and terminal audit records before inspecting the file.
4. Stop the host, verify complete worker and Bubblewrap teardown, then independently read the raw `pet-state` file. Require exact compact JSON, expected transitioned values, mode 0600, link count one, and a changed SHA-256.
5. Restart the same reviewed revision with the same state root and a fresh audit root. Require a second successful read and a visible marker matching the independently observed post-write bytes. A second screenshot without a second read audit is not persistence proof.

Keep the seeding step outside the sandbox only as test setup and label it as such. It proves backend compatibility, not plugin authority. The write leg proves that only an exact granted broker operation can mutate the private state; the restart leg proves durability and restoration.

## Security and penetration matrix

Keep known-good and malicious revisions separate. At minimum attempt:

- direct IPv4, IPv6, Unix, D-Bus, Wayland, SSH/GPG agent and credential-store access;
- reads of home, `/proc`, host runtime directories, another plugin revision and another plugin's private state;
- direct `Process`, shell, `gh`, `curl`, helper and sidecar execution outside declared sandbox-local executables;
- broker operation spoofing, undeclared operation names, widened scopes, stale generation and epoch, replayed correlations, forged descriptors and malformed frames;
- definition digest substitution, adapter mismatch, grant-store replacement, revision mutation and symlink/path races;
- sidecar descriptor inheritance, child escape, fork/task exhaustion, output flooding, oversized images, render floods and crash loops;
- revocation before dispatch, during asynchronous work and after provider effect but before result delivery;
- hostile notification text, audio paths, storage keys and payloads, with audit-secret scanning afterward.

For every case record the expected boundary, observed result, audit decision, worker/scope lifecycle, and whether any external effect occurred. A denial without an audit record or a worker crash without complete cgroup teardown is a failure.

The two required sidecar gates are `plugin-sidecar-supervisor` and `plugin-sidecar-real-bwrap`. The real probe must prove that privileged control, broker and render descriptors cannot be inherited or reopened through `/proc`; host and home canaries are absent; D-Bus and Wayland environment is absent; and nested namespace creation is denied by the production-equivalent `--disable-userns` policy.

## VM route

The authoritative graphical route remains the sibling `omarchy-iso` harness. It requires KVM, OVMF, QEMU, socat, ImageMagick and Tesseract, installs into a 40 GB sparse qcow2 base, then runs each test from a throwaway overlay. Build a current ISO after package/install changes; otherwise an installed Omarchy 4.x base plus this `/opt` lab is sufficient and preserves the installed schema-v1 environment.

The local 3.8.4 ISO boots under KVM on this machine, but its older installer and the current harness disagree at the keyboard-layout OCR step. Do not substitute manual keystrokes and call that reproducible evidence. Either harden the harness's OCR observation, use a current ISO, or provision a base image through an independently logged unattended path. CI must expose `/dev/kvm`, allow user/PID/network namespaces, support `SO_PASSCRED`, provide a graphical session inside the guest, and retain qcow overlays, serial logs, QMP screenshots, audit exports and provenance. Container-only tests do not replace the VM because they cannot prove the installed compositor, user service, package ownership and nested Bubblewrap boundary together.

## Cleanup

Stop all lab hosts, verify no worker or transient scope remains, archive evidence, and remove only the exact digest-named root. The helper prints but does not execute the removal command:

```bash
native/plugin-runtime/lab/omarchy-plugin-security-lab cleanup-command "$lab_root"
```

Never recursively remove `/opt/omarchy-plugin-security-lab` as a whole. Preserve the candidate while evidence refers to its digest.
