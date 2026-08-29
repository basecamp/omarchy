# Plugin Security Compatibility Study

## Purpose

This study tests the proposed secure plugin model against real community plugins. It maps what each plugin does today to the broker operations, remote-QML surface roles, and trusted portals it would need tomorrow, and distinguishes reusable product logic from code that must cross the new security boundary.

It is a design input, not a security review or endorsement of the sampled plugins. A listed behavior may be implemented carefully today and still require migration because schema-v1 QML runs with the authority of `omarchy-shell`.

## Corpus and sampling method

The source corpus is the [community marketplace](https://github.com/HANCORE-linux/omarchy-plugin-marketplace) snapshot generated at `2026-08-28T02:14:22.533Z`, repository commit `b04f0252d0728fe681d944d065b0ae2881ee5c15`.

- `registry.json` contains 1,575 sources: 1,573 plugin sources and 2 suites.
- 1,516 sources have an automated security-baseline result.
- The generated catalog expands suites and multi-plugin repositories to 1,613 entries, of which 1,331 are installable and 1,015 are marked verified.
- Catalog kinds are dominated by 1,399 bar widgets, followed by 98 overlays, 71 services, 28 panels, 8 bars, 5 generic plugins, 2 suites, and 2 combined-kind labels.

The marketplace baseline is useful supply-chain evidence, but its detected capabilities concentrate on installers, privilege use, package managers, service management, remote builds, and bundled binaries. It does not provide a complete runtime inventory of ordinary QML access to files, processes, sockets, the clipboard, Wayland protocols, D-Bus, or injected shell objects. The examples below were therefore inspected at their marketplace-validated upstream commits.

The sample is deliberately capability-stratified rather than random. It includes low-authority local widgets, authenticated command-line integrations, credentials and keyrings, screen capture, clipboard and input injection, arbitrary Internet APIs, local control sockets, Bluetooth and media buses, Docker, proxy mutation, package updates, compositor automation, plugin self-management, and a complete shell suite.

### Pinned sources

| Catalog id | Source | Inspected commit |
|------------|--------|------------------|
| `syskey8.pomodoro` | https://github.com/syskey8/omarchy-pomodoro | `9d1d7858aa1e258e244887cff8ff588d6efcc2fc` |
| `io.github.mohuddle.myjournal` | https://github.com/mohuddle/omarchy-myjournal | `f2f9453249772bce156db579ed9f9db42f413f48` |
| `37signals.basecamp` | https://github.com/basecamp/omarchy-basecamp-plugin | `9542960381517db9ab25cdb373b9eeb4f41315aa` |
| `y4gg.1password-popover` | https://github.com/y4gg/1password-popover | `02dd36c3d18d7ce28b22a030c8de0c5d8de638d5` |
| `io.github.sasirulk.totp` | https://github.com/sasiruLK/omarchy-totp | `ce2e759e272b353e98d46977487d2671d8f55446` |
| `ahasdemir.ai-grammar` | https://github.com/ahasdemir/hypr-ai-grammar | `5fa625e6298a273a1fb09528756d4974fb8db050` |
| `io.github.atif-1402.ai-panel` | https://github.com/atif-1402/ai-panel | `9af428b76a54a88b217334e8b9d03a999f827544` |
| `io.github.thisisgm.omapods` | https://github.com/thisisgm/omarchy-pods | `fff7fec600a5b9a61cdb40e93eccbcceb4b8f824` |
| `k53n0.browser-picker` | https://github.com/K53N0/omarchy-browser-picker | `680ad11780f5ff7488ebaec6cccc5429f5e0e956` |
| `shokupan.dpms-guard` | https://github.com/austin-karren/omarchy-dpms-guard | `b2be42638d5bb7b0eebd780485f1c95bc3049c1d` |
| `djjeane.docker-monitor` | https://github.com/djjeane/omarchy-docker-plugin | `81c95ec532b255d5d2bc98f6ff42c936608e9ead` |
| `io.github.lijiawei0305-pixel.mihomo` | https://github.com/lijiawei0305-pixel/omarchy-mihomo-plugin | `ce13a59c74a9c5044f2a6e30df58fb0da300039e` |
| `b.omashot` | https://github.com/brianblakely/omashot | `09eddf466bbe00e917a3e6de0840166ff727dfff` |
| `omarchy-overview` | https://github.com/AyushKr2003/omarchy-overview | `b09c227ba43182bebf101e5882147029fdddf7f1` |
| `b.peek` | https://github.com/brianblakely/peek | `23850a56f0e6e83d0e761b50e4fbce41e7ded24a` |
| `quickshell.spotify` | https://github.com/stappmus/Omarchy-Spotify | `f93b2f9333b7450b96a4c7843a11a2dd508235f8` |
| `dizziee.system-updates` | https://github.com/JJDizz1L/dizziee.system-updates | `67c099f74834414324914d5d0550cb728973771f` |
| `jltrench.textify` | https://github.com/jltrench/textify | `1d6f66dc95d8b9c4d56c9fb2e5f30613fb8ac7f5` |
| `b.okomart` | https://github.com/brianblakely/omarchy-plugins | `c8ff3b2f5377c72c8a854c6183617602f904ee62` |
| `lacuna.shell-suite` | https://github.com/OldJobobo/lacuna-omarchy-plugins | `ec309f8203097934ae409c9412e4eb3ba443bc3b` |

## What the sample changes in the model

The sample supports four distinct migration lanes:

| Lane | Existing shape | Secure destination | Typical author effort |
|------|----------------|--------------------|-----------------------|
| A: local QML | Timer, model logic, private state, small widget | Sandboxed QML process plus a remote bar or panel surface | Low |
| B: broker adapter | Existing CLI, service, or web API with bounded operations | Sandboxed QML process plus a typed broker adapter | Medium |
| C: privileged desktop integration | Clipboard reads, input injection, screencopy, URL-handler registration, compositor mutation, device buses, or package updates | Purpose-built broker API, trusted consent UI, and often a portal-style interaction | Medium to high |
| D: host extension | Complete multi-surface shell, lifecycle manager, or integration requiring trusted prompts | Trusted first-party component or explicitly unsafe host-code package | High; not an ordinary secure plugin |

This is why adding permissions to the existing schema is insufficient, but also why “every plugin must be rewritten from scratch” is inaccurate. Pure JavaScript models, parsers, reducers, ranking, protocol clients, domain behavior, and much of the visual QML are frequently reusable. Ambient effects, injected host objects, and direct surface ownership are the parts that must change.

## Representative migration matrix

The proposed operation names are design placeholders. They show the required granularity; they are not a commitment to final spelling.

| Plugin and pinned commit | What exists today | Secure form tomorrow | What must change | Lane |
|--------------------------|-------------------|----------------------|------------------|------|
| `syskey8.pomodoro` `9d1d785` | Timer state, a panel and bar status, `pw-play`, and `omarchy-notification-send` | Sandboxed remote QML keeps the custom timer/progress scene; worker-owned timer and private state; brokered sound and notifications | Reuse the model and visual QML. Replace the root surface and the two processes with the remote-view bootstrap, `audio.play-cue`, and `notifications.send`. | A |
| `io.github.mohuddle.myjournal` `f2f9453` | Journal CRUD and search backed by JSON and text files in a plugin-selected directory, with a keyboard-focused layer-shell panel | Remote QML editor and list in a granted panel surface; private broker storage by default; optional export/import through user-selected file handles | Reuse the journal model and panel scene. Replace `FileView`, `mkdir`, and direct layer-shell ownership. Decide whether the files are private plugin data or user-owned documents. | A |
| `37signals.basecamp` `9542960` | Invokes an authenticated `basecamp` CLI for status, account and notification operations; opens Basecamp links; copies setup commands; renders a rich notification panel | Registered Basecamp adapter with enumerated operations; `open-uri` limited to Basecamp HTTPS links and fresh gestures; remote QML bar and notification panel | Reuse response parsing, sorting, read-state logic, tests, and visual QML. Replace every `Process`, URL open, clipboard command, IPC handler, root surface, and host-object reference. | B |
| `y4gg.1password-popover` `02dd36c` | Long-lived helper talks to the 1Password desktop SDK, returns non-secret descriptors, and sends selected secrets directly to a sensitive one-paste clipboard | Remote QML retains the popover; credential-provider adapter returns opaque item and field handles; broker performs a one-shot `credentials.copy-field` action without returning the secret to the worker | Keep ranking, descriptor UI logic, and most visual QML. Move the helper behind Omarchy or a separately trusted provider service and replace direct layer-shell ownership. Avoid a generic permission to read passwords. | B/C |
| `io.github.sasirulk.totp` `ce2e759` | Stores secrets through `secret-tool`, keeps an account index in a file, generates codes locally, scans QR codes with `grim`/`slurp`/`zbarimg`, copies or types codes, and supports import/export/purge | Remote QML retains the authenticator panel; plugin-private secret store with opaque secret handles; user-gesture screen-region capture; QR decode service; sensitive clipboard write; separately confirmed focused-input action; file handles for import/export | Reuse TOTP calculation, account model, and panel QML. Replace keyring subprocesses, raw file access, screen capture, clipboard, typing, shell pipelines, and direct surface ownership. | C |
| `ahasdemir.ai-grammar` `5fa625e` | Reads the primary selection or clipboard, sends text to Gemini with `curl`, writes the result to the clipboard, and can paste it into the focused application with `wtype` | Remote QML retains the editor and preview; gesture-scoped selection read; credential handle; HTTPS request restricted to the selected provider; separate user actions for clipboard write and trusted focused-input confirmation | Reuse prompts, response parsing, and panel QML. Replace the shell script and direct clipboard/input/network access. The grant UI must explain that combining clipboard read with network access can disclose selected text. | C |
| `io.github.atif-1402.ai-panel` `9af428b` | Streaming multi-provider chat, Ollama support, attachments, clipboard history, saved chats and prompts, URL opening, favicon fetches, and saving code to Downloads; API keys are held in an owner-only JSON file despite the `KeyringStorage` name | Remote QML retains the rich chat experience; broker-held provider credentials; scoped HTTPS and loopback-provider APIs; private chat storage; user-selected attachment and export handles | Much of the provider strategy, conversation model, Markdown/code UI, and panel scene can survive. Replace generated curl scripts, direct files and clipboard history, broad Downloads writes, URL/image fetches, secret storage, shell execution, and direct layer-shell ownership. | B/C |
| `io.github.thisisgm.omapods` `fff7fec` | Plugin queries a bundled `librepods` daemon; setup builds/installs it and manages a user service. The daemon uses raw Bluetooth, BlueZ/system D-Bus, MPRIS, PulseAudio, persisted pairing keys, and can restart WirePlumber | Separately packaged and reviewed hardware provider with a narrow Omarchy adapter; explicit device selection; scoped Bluetooth observe/control, media control, audio-route control, and service lifecycle operations | The thin plugin model/UI can migrate. The large daemon is not made safe by a QML sandbox and needs its own package, sandbox, bus policy, device access policy, credential storage, and update lifecycle. | B/C |
| `k53n0.browser-picker` `680ad11` | Installs a desktop URL handler, enumerates browser profiles from browser configuration, becomes the system default browser, stores routing rules, launches chosen profiles, and uses focused layer-shell UI | Trusted URL-routing service receives an opaque URL activation; remote QML chooser in a granted focusable overlay; `applications.browser-profiles` enumeration; private routing state; explicit `default-handler.set` consent; constrained application launch | Reuse ranking, fuzzy matching, rules, migration logic, and chooser QML. Replace browser-profile file scanning, default-handler mutation, arbitrary process launch, FileViews, shell IPC, and direct layer-shell ownership. URL-handler registration must be a high-visibility system integration, not a routine network permission. | C |
| `shokupan.dpms-guard` `b2be426` | Reads an injected lock service, polls shell idle state and Hyprland monitor DPMS state, then runs an Omarchy display-off command while locked | Event subscription to trusted lock, authentication, idle, and display state; one narrow `display.dpms-off-while-locked` automation registered with an explicit condition | Reuse the state machine and safety gates. Replace host-object access, runtime-directory discovery, shell pipelines, `hyprctl`, and brightness command execution. This is a good test for broker-enforced conditional authority. | B/C |
| `djjeane.docker-monitor` `81c95ec` | Runs Docker CLI commands to list containers and stats, stream logs, and start, stop, restart, pause, unpause, or kill containers | Remote QML retains the monitor panel; Docker adapter with separate `docker.observe`, `docker.logs`, and `docker.control` grants; resource scope by context, project, or container; destructive actions require a fresh gesture and confirmation | Reuse JSON normalization, UI model, and panel QML. Replace the Python/shell/CLI bridge, direct surface ownership, and ambient Docker access. Omarchy no longer grants Docker daemon access by default, but the socket is host-root-equivalent authority whenever the user explicitly enables sudoless Docker, so never expose it to the worker. | B/C |
| `io.github.lijiawei0305-pixel.mihomo` `ce13a59` | Reads Mihomo endpoint and secret from flags/config, calls and streams its control API, changes modes and proxies, and mutates desktop proxy state through gsettings, dconf, and the systemd user environment | Remote QML retains the panel; Mihomo control adapter with opaque credential handling and endpoint pinning; read-only traffic/config streams separated from control; independent `network.proxy-system` permission with rollback and confirmation | Reuse API response models and panel QML. Replace configuration discovery, curl, secret exposure, direct proxy settings, systemd environment mutation, and direct surface ownership. Localhost access must be scoped like network access, not treated as harmless. | B/C |
| `b.omashot` `09eddf4` | Full-screen layer-shell capture UI, region/window selection, frozen frames, screenshots, screen recording, keystroke overlay, clipboard images, saved files, Hyprland event handling, and shell IPC | Remote QML retains custom capture decoration and controls inside a granted overlay; a trusted capture portal owns the authoritative scope and confirmation; broker returns capture/recording handles; destination picker, clipboard, file-save, and input observation are separately granted | Reuse capture policy, naming, orchestration, and much of the overlay QML. Direct compositor surfaces, screencopy, global input observation, and destination authority move into trusted code. | C/D |
| `omarchy-overview` `b09c227` | Layer-shell workspace overview with live `ScreencopyView` thumbnails; reads clients, monitors, layers and workspaces; focuses, moves, closes, and toggles special workspaces | Remote QML overview consumes sanitized workspace data and broker-provided preview handles; named compositor actions are separated into focus, move, close, and special-workspace capabilities | Layout algorithms and most visual QML are reusable. Replace direct Hyprland objects, `hyprctl`, screencopy, focus grabs, layer-shell ownership, and dispatch calls. Close and move should not be implied by read-only overview access. | C/D |
| `b.peek` `23850a5` | Watches Hyprland focus/window events and injects window rules that fade and disable floating windows | Narrow trusted compositor automation with declared rule template, affected-window predicate, enable/disable state, and automatic cleanup | Reuse the predicate/state logic. Replace raw Hyprland events and arbitrary `hyprctl eval`; the broker must constrain which rule properties and windows can be changed. | C |
| `quickshell.spotify` `f93b2f9` | Rich Spotify client using MPRIS, Spotify Web API and OAuth, keyring refresh tokens, a built Rust playback backend or spotifyd, local sockets, systemd user units, package installation, clipboard, and URL opening | Remote QML retains the media browser and player; media observe/control API plus a Spotify provider adapter; broker-held OAuth; bounded HTTPS; separately packaged playback provider with private socket | Reuse the API/model and visual QML selectively. Split runtime installation from plugin activation; replace MPRIS access, keyring processes, socket access, service control, package installation, network, clipboard, URL opens, files, and direct surfaces. | B/C |
| `dizziee.system-updates` `67c099f` | Checks pacman, AUR, Flatpak, and Omarchy updates, then launches terminal commands including a direct `sudo pacman -Syu` that bypasses Omarchy's managed update pipeline | Read-only `updates.observe` broker; trusted action launches only registered update workflows such as `omarchy update`, with terminal/polkit interaction owned by Omarchy | Reuse counts and presentation model. Replace arbitrary terminal command strings and direct package-manager paths. A plugin must not be able to request an environment-variable bypass of Omarchy's update guard. | C |
| `jltrench.textify` `1d6f66d` | Selects or captures a screen region, preprocesses it with ImageMagick, runs local Tesseract OCR, keeps history, and copies text to the clipboard | Remote QML retains the OCR panel; trusted capture portal returns an opaque image handle to a sandboxed OCR worker; bounded local compute; private history; gesture-scoped clipboard write | The Rust OCR engine, language model, and panel QML are largely reusable. Replace direct `slurp`/`grim`, raw temporary paths, `wl-copy`, and direct surface ownership. The worker should receive image bytes or a handle, never compositor access. | C |
| `b.okomart` `c8ff3b2` | Marketplace browser that fetches catalogs and GitHub metadata, clones and inspects repositories, installs/updates/removes plugins, manages media caches, and coordinates Hyprland window behavior | Omarchy-owned plugin manager calling the trusted lifecycle service; its storefront may retain custom QML, while installation and permission prompts remain host-owned | Reuse catalog parsing, storefront QML, and UX ideas. Move installation, Git access, validation, grant changes, revision activation, recovery, and cache ownership into Omarchy. Do not define a general `plugins.manage` grant for third-party plugins. | D |
| `lacuna.shell-suite` `ec309f8` | Complete shell distribution with a replacement bar, menu, many panels and overlays, settings persistence, Hyprland configuration, audio, Bluetooth, network, power, recording, weather, media, and an installer | Trusted shell pack with package-level review and explicit installation, or decomposition into independent secure plugins backed by standard system APIs | Individual models and widgets can migrate incrementally. The full suite cannot be represented as an ordinary untrusted plugin without making the entire shell UI protocol remotely programmable, recreating `unsafe.host-code` under another name. | D |

## Required broker APIs derived from the examples

### Safe core

- `storage.private`: quota-bound structured state, blobs, and migrations.
- `notifications.send`: bounded title/body/category, rate limited, with no arbitrary actions unless separately declared.
- `audio.play-cue`: named system sounds or size-bounded plugin assets, not arbitrary host paths.
- `open-uri`: scheme and host constrained, requiring a fresh user gesture for plugin-supplied destinations.
- `files.open` and `files.save`: trusted picker returns revocable handles; no host path is disclosed unless strictly necessary.
- `clipboard.write`: typed text/image payload, size bound, optionally sensitive and one-shot.
- `clipboard.read-selection`: fresh-gesture access to the current selection only; no ambient clipboard-history permission in the initial API.
- `input.insert-text`: high-risk, fresh-gesture operation with trusted preview and focused-application identity shown to the user.

### Service adapters

- `command.invoke` only through installed, versioned adapters with enumerated operations and validated arguments. The sample needs Basecamp initially; raw executable names and arbitrary argv are not a secure API.
- `credentials`: provider-specific search/descriptor operations and broker-executed use or copy actions. Prefer opaque handles to returning secret bytes to the worker.
- `http.request`: exact schemes, hosts, methods, redirect policy, request/response limits, and rates. Loopback and Unix-socket HTTP need explicit scopes.
- `media.observe` and `media.control`: player metadata and separately granted transport/volume/queue actions.
- `docker.observe`, `docker.logs`, and `docker.control`: resource-scoped adapters, never a mounted Docker socket.
- `network.observe`, provider-specific controller APIs, and `network.proxy-system`: read and mutation are distinct; proxy mutation needs atomic rollback.
- `bluetooth.observe`, `bluetooth.control`, and `audio.route`: device-scoped operations. Raw Bluetooth protocols remain outside the generic plugin worker.
- `updates.observe` and trusted update workflows: no arbitrary package-manager or privileged command execution.

### Shell and compositor

- Sanitized subscriptions for lock, authentication-in-progress, idle, monitor, workspace, toplevel, fullscreen, theme, and layout state.
- Named compositor actions for workspace focus, window focus, move, close, rule application, and DPMS. Observation never implies mutation, and close is distinct from focus or move.
- Trusted portals for screencopy, region/window selection, recording, and live preview nodes.
- Trusted registration for URL handlers and other desktop defaults, with a clear system-level consent surface and recovery path.
- Plugin-scoped named commands replace arbitrary `IpcHandler` registration. Callers address a plugin and declared command; plugins cannot claim another namespace.

## Required remote-QML surface model derived from the examples

The plugin retains arbitrary QML for all ordinary presentation. Omarchy standardizes surface envelopes and trusted portals, not visual components.

The sample requires these surface roles:

1. Embedded bar slots with plugin-controlled pixels, transparency, animation, bounded sizing, pointer input, tooltips, and popover activation.
2. Focusable panels, popovers, and slide-outs with plugin-controlled layout, text input, lists, Markdown, streaming content, charts, calendars, images, and custom controls.
3. Transparent desktop overlays and underlays for pets, ambience, capture affordances, and transient indicators, with bounded input regions and z-order.
4. Ordinary sandboxed windows for settings and application-scale interfaces when a restricted security-context Wayland connection is sufficient.
5. Broker-provided media handles for images, captured frames, album art, favicons, and live window previews so a plugin can compose them without receiving arbitrary file or screencopy access.

The surface protocol controls dimensions, monitor assignment, role, z-order, exclusive zone, keyboard focus, pointer regions, frame rate, buffer size, visibility while locked, and whether full-screen coverage is possible. QML inside the assigned region retains arbitrary styling and composition.

Trusted portals remain necessary for file open/save, credential selection, screen/window/region capture, focused-input preview, URL-handler setup, package/update confirmation, permission changes, and destructive system actions. Authentication, polkit, permission prompts, global input observation, lock-screen placement, and the host-owned surface inspector never render inside plugin QML.

## Permission composition matters

Reviewing permissions one at a time is insufficient. The examples expose dangerous combinations:

- clipboard or selected-text read plus network can exfiltrate user content;
- screencopy plus network can exfiltrate anything visible;
- credential read plus clipboard, files, or network defeats the purpose of a credential broker;
- input insertion plus hidden or ambiguous focus can act on the wrong application;
- URL-handler registration plus external launch can intercept sensitive login and payment links;
- Docker control plus broad mounts in a container is effectively arbitrary host control;
- package management, service control, or compositor command templates can become generic code execution;
- live toplevel metadata plus screencopy reveals more than either permission description suggests.

The grant UI should therefore show a composed risk summary and elevate or reject combinations. Some APIs should be designed so the sensitive value never reaches the worker: the broker can copy a password, submit a token to an HTTP adapter, open a selected URL, or feed a captured image to an OCR operation directly.

## Migration tooling implied by the sample

A useful migration tool can statically inventory, but not automatically approve, the following:

- plugin kinds and entry points;
- `Quickshell.Io`, `FileView`, `Process`, `Socket`, `execDetached`, clipboard access, URL opening, and IPC handlers;
- Wayland, layer-shell, screencopy, Hyprland, MPRIS, Bluetooth, networking, PipeWire, notifications, and D-Bus imports;
- executable names and literal argument prefixes;
- referenced filesystem roots, environment variables, URL hosts, Unix sockets, and systemd units;
- writes to shell configuration, desktop files, default handlers, services, package databases, or privileged paths;
- injected `shell`, `bar`, registry, and cross-plugin object access;
- unbounded output, response, image, model, timer, and restart behavior.

The output should be a generated migration worksheet with three columns: detected behavior, proposed broker/UI mapping, and an author decision. It must flag dynamic shell strings, computed paths, computed URLs, native binaries, and installers for manual review rather than guessing a safe permission.

## Reference implementation consequences

The original tiny counter fixture still proves isolation and grants, but it does not prove that the model preserves the feature that distinguishes Omarchy plugins. The reference PR should include three fixtures:

1. A local Pomodoro-style widget proves Lane A: custom animated QML, forwarded input, timer state, private persistence, named actions, optional sound, and notifications.
2. A transparent pet or slide-out proves freeform QML, alpha, animation, input regions, a non-bar surface role, and host inspection and termination.
3. A Basecamp-style fake adapter proves Lane B without requiring a real account: enumerated authenticated-service operations, a custom QML list, an `open-uri` action, denial of undeclared CLI operations, response bounds, and update permission diffs.

The PR should also ship the inventory command in report-only mode and run it against representative fixtures. Screen capture, credentials, input injection, device buses, Docker, package updates, full panels, and compositor mutation should remain denied and unimplemented until their APIs and trusted consent surfaces are separately reviewed.

## Conclusions

- A substantial class of plugins can migrate without losing product behavior, custom visual design, or most of their existing QML; their root surfaces and ambient effects still change.
- Rich integrations are feasible only if Omarchy supplies domain adapters, remote surface envelopes, and trusted security portals; a generic process or D-Bus permission would collapse the model back to ambient authority.
- Some useful operations require portals or host mediation, not merely sandbox mounts: credentials, clipboard reads, input insertion, screencopy, URL handlers, updates, and destructive compositor actions.
- Full visual bars can use a secure host-owned replacement surface. Complete shell suites and plugin managers may still be a different trust class when they require trusted prompts, lifecycle authority, or effectively unrestricted system integration.
- The compatibility SDK, inventory tool, and before/after fixtures are part of the security model. Without them the architecture is enforceable but unlikely to be adopted.
