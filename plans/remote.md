# Plan: Remote — finish Sunshine/Moonlight into a real remote desktop

Revision 1.

## Problem

Omarchy already leans Sunshine/Moonlight: `moonlight-qt` ships preinstalled (`bin/omarchy-install-preinstalls`) with a fullscreen + idle-inhibit window rule (`default/hypr/apps/moonlight.lua`), and `bin/omarchy-install-service-sunshine` installs the host, opens the Moonlight ports for RFC1918 LANs and `tailscale0` via ufw, and drops a "Sunshine Admin" webapp. `manual/26-gaming.md` even advertises `omarchy install service sunshine`. But what exists is a game-streaming bootstrap, not a remote desktop. The gaps, in the order a user hits them:

- **Two start paths for one daemon.** The installer runs both `systemctl --user enable --now sunshine` *and* appends `o.launch_on_start("sunshine")` to `~/.config/hypr/autostart.lua`. On every login the systemd user manager starts the unit (upstream ships it `WantedBy=graphical-session.target` with `Restart=on-failure`) while Hyprland's autostart launches a second copy through `uwsm-app`; whichever loses the port-bind race flaps and litters the journal. The autostart line was presumably insurance against the unit lacking `WAYLAND_DISPLAY` — insurance Omarchy doesn't need, because uwsm imports the session environment into the user manager before `graphical-session.target` is reached (it's how every other session unit in `default/systemd/user/` works).
- **Pairing is the weak link.** First contact is a browser pointed at `https://localhost:47990` with `--ignore-certificate-errors`, where you invent a username and password over a self-signed cert, then transcribe a PIN from Moonlight into a web form. That's three UI hops and a certificate warning for what is, protocol-wise, one authenticated POST.
- **Streaming hijacks the physical screen.** Sunshine captures a real monitor, so "remote desktop" today means watching your own desk chair's screen — and means nothing at all when no monitor is attached. There is no virtual display, which is the single feature that separates game streaming from remote desktop.
- **Audio is all-or-nothing.** Sunshine captures the default sink's monitor, so the stream hears whatever the speakers at the desk are playing, and the desk hears everything the remote session does.
- **No menu presence.** Despite the manual advertising it, there is no Sunshine entry anywhere in `default/omarchy/omarchy-menu.jsonc` — not under Install > Service, not under Remove. The feature is invisible unless you already know the command.
- **Install-order coupling with Tailscale.** The ufw rules for `tailscale0` are only added if the interface exists at install time; `omarchy-install-service-tailscale` knows nothing about Sunshine's ports. Install Sunshine first, Tailscale second, and the tailnet — the whole point of remote access — is silently closed.
- **Uninstall is only half-symmetric.** `omarchy-remove-service-sunshine` closes ports and removes the webapp and autostart line, but leaves `~/.config/sunshine/` (pairing state, credentials, apps) behind, and knows nothing about the virtual display or audio plumbing this plan adds.

## Shape

One blessed path — Sunshine hosting, Moonlight connecting — finished end to end. "End to end" means: pick Sunshine from the menu, pair from a terminal with a PIN, connect from any Moonlight client on the LAN or tailnet, land on a dedicated remote workspace sized to your client (or deliberately mirror the physical screen), hear the session's audio without broadcasting it at the desk, disconnect without orphaning a single window, and uninstall without leaving a trace. All of it inside the posture the installer already got right: ports open to private networks and the tailnet only, never the internet.

The work is a rework of the two existing scripts plus a small new `sunshine` command group (precedent: the `tailscale` group), a managed slice of Sunshine's configuration, menu entries, a migration for existing installs, tests, and a manual section. No new daemons, no new packages beyond what's already in the omarchy repo.

## Rejected approaches

- **wayvnc, or an xrdp/VNC-RDP chain**: wayvnc (0.10.1 in extra) does capture Hyprland via wlr-screencopy, but VNC is unencrypted-by-default, software-encoded, and pointer-laggy; chaining xrdp on top adds a protocol translation layer that breaks whenever Hyprland's wlroots divergence shifts under it. No hardware encode means it loses to Sunshine on every axis Omarchy cares about (latency, battery, fidelity), and we'd still have to solve pairing, virtual displays, and audio ourselves.
- **RustDesk**: packaged (1.4.9 in the omarchy repo) and tempting for its built-in relay story, but Hyprland hosts still fail in practice — it wants the `org.freedesktop.portal.RemoteDesktop` portal, which `xdg-desktop-portal-hyprland` does not implement (hyprwm/xdg-desktop-portal-hyprland#252, still open; rustdesk/rustdesk#9026 documents the Hyprland-specific failure). Blessing a host that can't host on our own compositor is not a v1.
- **Waiting for the RemoteDesktop portal**: same issue. Sunshine sidesteps the portal entirely — capture via wlr-screencopy, input via uinput (the package ships the udev rule) — which is exactly why it's the one stack that works on Hyprland today. The plan builds on that, and can revisit portal-based options if #252 ever lands.
- **waypipe**: forwards individual Wayland apps, not a desktop; a different product.
- **Building a Fluid-equivalent from scratch**: a bespoke streaming stack is a multi-year protocol, codec, and client-matrix project. Omarchy's leverage is integration taste, not reinventing NVENC negotiation. Sunshine/Moonlight is mature, hardware-accelerated, cross-platform on the client side, and already half-wired into the repo.
- **A logged-out remote login mode** (what gnome-remote-desktop grew): Sunshine attaches to a running session, and Hyprland has no system-daemon mode to attach to. Omarchy's SDDM autologin means a booted machine has a session anyway; the honest constraint is full-disk encryption's passphrase prompt, covered under open questions rather than papered over.

## Design

### One daemon, one start path

The systemd user unit wins. It has restart-on-failure, journal logging, a clean `is-active` answer for guards and status, and — because uwsm imports `WAYLAND_DISPLAY` and friends into the user manager — a complete graphical environment by the time `graphical-session.target` pulls it in. The installer keeps `systemctl --user enable --now sunshine` and stops touching `autostart.lua`; a migration (epoch-named under `migrations/`) deletes the `o.launch_on_start("sunshine")` line from existing users' `~/.config/hypr/autostart.lua` so the double start dies everywhere, not just on fresh installs. The remove script keeps its `sed` cleanup for one release as belt-and-braces, then that too can go.

### Capture backend: wlr-screencopy, declared explicitly

Omarchy writes `capture = wlr` into its managed section of `~/.config/sunshine/sunshine.conf` instead of letting Sunshine probe. Two reasons, both structural:

- KMS capture reads real DRM CRTCs, so it needs `CAP_SYS_ADMIN` on the binary *and* it fundamentally cannot see a virtual output — a headless Hyprland output has no CRTC. Sunshine used to crash on headless connectors outright (LizardByte/Sunshine#2955, fixed by skipping them), but "skipped" still means "not capturable". Since the virtual display is the centerpiece of this plan, KMS is disqualified regardless of its marginal latency edge.
- wlr-screencopy is the interface Hyprland actually maintains (`hyprland.portal` declares ScreenCast/Screenshot/GlobalShortcuts/InputCapture — capture is first-class), captures any output including headless ones, needs no capability bits, and feeds VAAPI/NVENC the same dmabufs.

Input needs no decision: Sunshine injects through uinput with the udev rule its package installs, below the compositor, so the missing RemoteDesktop portal is irrelevant on the host side.

### Command surface

The lifecycle pair stays where it is: `omarchy-install-service-sunshine` and `omarchy-remove-service-sunshine` are the Install > Service idiom (1Password, Dropbox, Tailscale all live there), the manual already names the route, and renaming to `setup-` would break it for no gain — `setup-` in this repo means an interactive wizard you re-run (`omarchy-setup-security-sshd`), while install/remove is a one-shot lifecycle, which is what this is. What grows is a `sunshine` group in `GROUP_DESCRIPTIONS` (`GROUP_DESCRIPTIONS[sunshine]="Sunshine remote desktop hosting"`), exactly as `tailscale` earned its group once it had verbs beyond install:

- `omarchy-sunshine-pair` — the terminal pairing flow (below).
- `omarchy-sunshine-clients` — list paired clients, unpair one or all (gum choose over `/api/clients/list` and `/api/clients/unpair`).
- `omarchy-sunshine-mode` — `dedicated | mirror | --status`, the display-mode switch (below), with `--status` for menu `checked` guards in the nightlight tradition.
- `omarchy-sunshine-display` — `# omarchy:hidden=true`; the prep-cmd do/undo hook Sunshine calls, never users.
- `omarchy-installed-service-sunshine` — hidden predicate in the `installed` group, mirroring `omarchy-installed-service-tailscale`: package present and unit active.

All carry `# omarchy:summary=` metadata per `agents/skills/command-metadata.md`, and `omarchy commands --check` keeps them honest.

### Pairing: a PIN in a terminal, not a certificate warning in a browser

Sunshine's web admin exists because most distros give it nothing better. Omarchy can do better with two facts: credentials can be set non-interactively (`sunshine --creds <user> <password>`), and pairing is one authenticated call (`POST /api/pin` with `{"pin": ..., "name": ...}`, basic auth).

- **At install**, before the unit ever starts, the installer generates a random password, runs `sunshine --creds omarchy <password>`, and stores it 0600 under `~/.local/state/omarchy/sunshine/credentials`. The user never invents web credentials; the first-run browser ceremony is gone. The managed config also sets `origin_web_ui_allowed = pc` explicitly so :47990 answers localhost only — the ufw rules already exclude it (only 47984/47989/48010 TCP and the stream UDP range are opened), and now Sunshine itself agrees.
- **`omarchy-sunshine-pair`** is bash + gum: prompt for the PIN Moonlight is displaying and a client name, `curl -sk -u "omarchy:$(<credentials)" -X POST https://localhost:47990/api/pin` with the JSON body, report success or a re-prompt on rejection. `-k` against loopback with basic auth is fine — the transport being vouched for is localhost, and the pairing protocol's own certificate pinning between Sunshine and Moonlight is untouched. The installer finishes by pointing at this command instead of launching the webapp.
- The **Sunshine Admin webapp** survives as the expert escape hatch for per-app tinkering (there is real depth in Sunshine's UI), but the installer stops auto-opening it, and whether it should exist at all is an open question below.

### The virtual display

The core of the plan. `hyprctl output create headless <name>` gives Hyprland a real output with no glass attached; wlr-screencopy captures it like any other. Wired into Sunshine's per-app prep-cmd do/undo pair, it turns the stream into a workspace of its own.

Omarchy manages `~/.config/sunshine/apps.json` with two entries, which are also the mode story:

- **"Remote Desktop"** (the default `omarchy-sunshine-mode dedicated` target): `prep-cmd` do runs `omarchy-sunshine-display up`, undo runs `omarchy-sunshine-display down`. No detached command — the "app" is the desktop itself, so the session lives exactly as long as the client is connected.
- **"This Screen"** (`mirror`): no prep-cmd; Sunshine captures the focused physical monitor. For showing your desk screen to a conference room, or driving a machine you're also sitting at.

`omarchy-sunshine-display up` does, in order:

1. `hyprctl output create headless sunshine` — a fixed, predictable name (custom names are supported; without one Hyprland invents HEADLESS-2, -3, … per session, which no config can target).
2. Size it to the client: Sunshine exports `SUNSHINE_CLIENT_WIDTH`, `SUNSHINE_CLIENT_HEIGHT`, and `SUNSHINE_CLIENT_FPS` into prep-cmds (verified against upstream docs — the names in this plan are exact), so `hyprctl keyword monitor "sunshine,${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}@${SUNSHINE_CLIENT_FPS},auto,1"` gives the phone a phone-shaped desktop and the MacBook a Retina-shaped one. A runtime `hyprctl keyword`, not a `monitors.lua` edit — this output is ephemeral and must never leak into the user's declared monitor config, and Omarchy's default `hl.monitor({ output = "" ... })` catch-all would otherwise claim it with the wrong scale.
3. Move an empty workspace there and focus it — the next-free workspace number, recorded in `~/.local/state/omarchy/sunshine/` alongside the output name, so `down` knows exactly what it created. The stream opens on a clean desk; the physical monitors keep their workspaces and their user.

`omarchy-sunshine-display down` (the undo, which Sunshine also runs when the client disconnects uncleanly) reverses it with care for Hyprland's output-removal behavior: when an output disappears, Hyprland evacuates its workspaces onto a surviving monitor — that is the safety net, not the plan. Before `hyprctl output remove sunshine`, `down` moves any windows the remote session opened onto the recorded workspace *number* (which survives the output), so nothing lands scattered across whatever monitor Hyprland picks, and then removes the output. If *no* physical monitor exists — the truly headless box — `down` still removes the output; the workspaces sit in limbo until the next `up` recreates a home for them, which is exactly what happens on the next connection. `up` is also self-healing: a leftover `sunshine` output from a crashed session is removed and recreated rather than trusted.

Two honest caveats, stated here so the rollout verifies them instead of discovering them: Sunshine selects which output to capture via `output_name`, whose wlr-backend matching semantics (numeric enumeration id vs. name string) must be pinned down on the shipped 2026.516 build — the design wants "capture the output named `sunshine` when it exists, the focused physical monitor otherwise," and if `output_name` can't express that per-app, the fallback is `omarchy-sunshine-mode` rewriting the global `output_name` and restarting the unit on mode switch, which is coarser but deterministic. And the headless-with-FDE case (passphrase prompt before SDDM autologin) is a real limit on "connect to a machine nobody is sitting at"; it goes to open questions, not under the rug.

### Audio

Mirror mode changes nothing: Sunshine captures the default sink's monitor and both ends hear the same thing, which is what mirroring means.

Dedicated mode gets a private sink. `omarchy-sunshine-display up` loads a null sink through PipeWire's pulse layer (`pactl load-module module-null-sink sink_name=sunshine-audio ...`, module id recorded in state), and the managed config sets `virtual_sink = sunshine-audio` so Sunshine switches the default sink to it for the duration of the stream and restores the previous default afterward; `down` unloads the module. The consequence is deliberate and worth stating plainly: during a dedicated-mode stream, the machine's audio belongs to the remote session — apps play into the virtual sink, the stream carries it, and the desk's speakers are silent. On a single-user machine that is the correct reading of "not stealing local audio": the person who is actually using the machine is the one holding the Moonlight client. The alternative — splitting audio per-application between two concurrent users of one seat — is a multi-seat feature PipeWire can theoretically express and no one would maintain.

### Security

The existing posture is the good part and stays: TCP 47984/47989/48010 and UDP 5353/47998–48010 opened only to 10/8, 172.16/12, 192.168/16 and `tailscale0`, tagged `omarchy-sunshine`, torn down by comment on removal. On top of that:

- The install-order coupling gets fixed by extraction: the Sunshine ufw rules move into an idempotent internal helper the install script calls, and `omarchy-install-service-tailscale` finishes by re-running it when Sunshine is installed (and vice versa — Sunshine's installer already handles the Tailscale-first order). Whichever service arrives second, the tailnet rules exist.
- `origin_web_ui_allowed = pc` and no ufw rule for 47990, ever: the admin surface is loopback-only by two independent mechanisms.
- `upnp = off` written explicitly in the managed config. Sunshine links miniupnpc; a remote desktop host must never ask the router to open the internet at it, and the manual says in one sentence why the answer for roaming access is Tailscale, not port forwarding.
- Credentials at `~/.local/state/omarchy/sunshine/credentials`, 0600, passed to curl via config-file/stdin rather than argv where it would show in `ps`.
- The pairing trust model is Sunshine's own client-certificate pinning established during the PIN exchange; Omarchy adds no cert of its own and removes the one place users were trained to click through a certificate warning.

### Managed configuration, user configuration

Sunshine's config is the user's, like everything in `~/.config`. Omarchy owns a delimited block in `sunshine.conf` (`capture`, `output_name`, `virtual_sink`, `origin_web_ui_allowed`, `upnp`) written idempotently by the installer and `omarchy-sunshine-mode`, and owns the two shipped entries in `apps.json` by name — regenerated on install, left alone otherwise, so a user who adds a Steam Big Picture entry in the admin UI keeps it. The remove script deletes only what Omarchy wrote, then offers (gum confirm) to purge `~/.config/sunshine/` entirely — pairing state included — since "remove the service" usually means "this machine stops being a host," but must not silently destroy pairings someone means to keep across a reinstall.

### Menu

Per `docs/menu.md` conventions, no `aliases` on any new entry:

- `install.service.sunshine` — `{"icon": ..., "label": "Sunshine", "disabled": "omarchy-pkg-present sunshine", "action": "omarchy-launch-floating-terminal-with-presentation omarchy-install-service-sunshine"}` — the catalog row that should always have existed, dimmed-with-✓ once installed like every Install row.
- `remove.service.sunshine` — the mirror image, `when: omarchy-pkg-present sunshine`, hiding what isn't there to remove.
- `setup.sunshine` — a submenu that only exists when installed (`when: omarchy-pkg-present sunshine`): **Pair Client** (floating terminal → `omarchy-sunshine-pair`), **Clients** (→ `omarchy-sunshine-clients`), **Dedicated Display** / **This Screen** rows with `checked` guards reading `omarchy-sunshine-mode --status` (registered in `GUARD_READERS` since two rows read it, as `menu-guards-test.sh` enforces), and **Admin** (the webapp, demoted from installer-auto-open to a menu row).

### Client side, and the scope line

Moonlight is preinstalled, has its window rule, and appears in the launcher; pairing *to* an Omarchy host is this plan's terminal flow plus a PIN. A connection helper (`moonlight-qt stream <host> "Remote Desktop"` wrapped in a picker) is cheap but premature — Moonlight's own grid UI already remembers hosts, and wrapping it before anyone asks is the kind of chrome the dots plan warns about. The manual documents the CLI one-liner for keybinding enthusiasts and stops there.

Reaching a **Mac or Windows** box *from* Omarchy is a real adjacent gap and explicitly not this plan. It is a different protocol stack (FreeRDP/Remmina toward Windows, nothing good toward macOS but VNC), a different trust model, and a different design center (client-only, no host work). Stapling it on here would dilute both; if demand shows up it's `plans/rdp.md`, and this plan's manual section links Remmina by name so the answer today is at least discoverable. RustDesk stays uninstalled by default for the host-side reasons above.

### Uninstall symmetry

`omarchy-remove-service-sunshine`, reworked to undo everything this plan creates: stop and disable the unit; run `omarchy-sunshine-display down` if state shows a live session (output removed, null sink unloaded, workspace evacuated); close the tagged ufw rules; remove the webapp; strip the legacy autostart line; delete `~/.local/state/omarchy/sunshine/`; offer the `~/.config/sunshine/` purge; drop the package. The menu needs no teardown — every entry is guarded on package presence and disappears on its own. A re-install after a remove-without-purge comes back paired, which is the correct reading of the two-step teardown.

## Rollout

- **Phase 1 — make what exists correct**: single start path + migration removing the autostart line; credentials at install; `origin_web_ui_allowed`/`upnp`/`capture` in the managed config; terminal pairing (`omarchy-sunshine-pair`, `omarchy-sunshine-clients`); the missing Install/Remove menu rows; ufw helper extraction and the Tailscale cross-call. Shippable alone and already a better product.
- **Phase 2 — the remote desktop**: `omarchy-sunshine-display` do/undo, managed `apps.json`, `omarchy-sunshine-mode`, the audio sink, the `setup.sunshine` menu. Gated on the two verification checkpoints from the design: `output_name` semantics against the shipped build, and disconnect/reconnect behavior under monitor add/remove churn on real hardware.
- **Phase 3 — polish**: `omarchy-sunshine-clients` unpair flows, docs, acceptance coverage.
- **Tests**: shell tests in `test/shell.d/sunshine-test.sh` for the pure logic — managed-config block idempotency, apps.json generation preserving user entries, ufw argument construction, state-file round-trips for `display up`/`down`, mode `--status` output; CLI metadata via `omarchy commands --check`; menu guard wiring via the existing `menu-test.sh`/`menu-guards-test.sh` conventions. Graphical acceptance per `agents/skills/acceptance-tests.md` in the ISO VM: install from the menu, unit active, ports open, `display up` creates and sizes the output and `down` leaves no orphaned windows (screenshot each state), remove leaves no unit/rules/state behind. Actual stream negotiation needs a Moonlight client and stays a manual checklist item in the PR, honestly labeled.
- **Docs**: a new `manual/52-remote-desktop.md` — hosting setup, pairing, the two modes, Tailscale-for-roaming, the FDE/headless caveat, and the Remmina pointer for the Windows-target gap; `manual/26-gaming.md` trims to game streaming and links over; `docs/` gets a short reference on the managed-config block and state files so future migrations know what Omarchy owns.

## Open questions

1. **`output_name` semantics on the wlr backend** — id or name, and when Sunshine enumerates outputs relative to prep-cmd execution. The design assumes per-session resolution after `up` runs; if the shipped build disagrees, mode switching falls back to config-rewrite-plus-restart. Phase 2 gates on the answer.
2. **Clipboard sync** — upstream has said no: text-only clipboard sync was proposed and closed as not planned (LizardByte/Sunshine#5384), and Moonlight has no transport for it. An Omarchy-side bridge (wl-clipboard over Tailscale between two Omarchy machines) is buildable but is a new sync daemon with a security surface, helps no Mac/Windows/phone client, and smells like scope creep. Leaning: explicit non-goal in v1, revisit only as its own plan.
3. **Headless boot under full-disk encryption** — the LUKS passphrase blocks the session a monitor-less host needs. TPM auto-unlock or remote unlock is its own security design. Document the limit in v1, or fold a TPM story in?
4. **Does the Sunshine Admin webapp survive** once pairing, clients, and modes have first-party surfaces — expert hatch, or the browser habit this plan exists to end?
5. **Mirror-mode geometry** — when client and physical resolutions disagree, let Moonlight scale (default) or mode-switch the physical monitor to match via the same prep-cmd env vars? Scaling is unobtrusive; mode-switching is what the game-streaming crowd expects.
6. **A bar presence** — dropbox/tailscale-style plugin showing "streaming now" with a disconnect action? Genuinely useful the moment someone streams *from* a machine they also sit at, but plugin work is its own discipline; leaning v2.
7. **A "Log out remote session" guard** — should `down` also close the windows the remote session opened instead of re-homing them, as a privacy stance for shared-desk machines? Leaning no: never destroy user windows automatically.
