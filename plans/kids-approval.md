# Plan: Kids approval — ask a parent, and the parent answers on their phone

Revision 2.

## Problem

`plans/kids.md` ships parent approval as two things: the polkit prompt a non-wheel session gets when it runs a privileged command, and a root-owned token that unpins plugin installs. Both assume the parent is at the child's keyboard. That leaves three gaps.

- The parent has to walk over. A child in the next room asks for a game; the parent stops what they are doing, comes to the child's screen, and types their password there. The password is the only credential on the machine that matters, and this flow teaches the child to watch it being typed.
- The prompt approves a program, not an intent. pkexec shows "Authentication is needed to run `/usr/bin/omarchy-kids-allow` as the super user". The parent cannot see the domain from the dialog, and a child who learns to open a terminal can put the prompt on screen at any time.
- The unlock token is a time window. `omarchy kids unlock` opens plugin installs for a set number of minutes, for any plugin. The parent approves a period, not a plugin.

Switching user, another tty, or `ssh` from another machine closes none of these for a parent. A parent is in the kitchen, at work, or in the car, with a phone in a pocket. If the phone is not the first way a parent answers, the parent stops answering, or hands the child the password.

The community built [omarchy-parentapproval](https://github.com/aphexddb/omarchy-parentapproval) for the parent with a phone: pair once by scanning a QR, confirm six digits bound to the phone's key, add the page to the Home Screen, allow notifications, and from then on the phone buzzes and one tap answers. Its parent experience is right. Its machine side is a root daemon, PAM rewriting, a sudoers grant for the child, and a hosted relay that serves the code holding the parent's key. None of that can ship in core.

The system: the child asks for a specific thing. The request waits in a root-owned queue. The parent's phone buzzes. The parent taps Approve or Deny. The phone signs the decision with a key that never leaves it. Root on the child's machine verifies the signature and fulfills the request. The parent's own session and `ssh` are the second and third ways in. There is no relay: the child's machine is the origin the phone talks to, reached over the parent's own tailnet.

## Shape

- A request is an intent, not a command. There are four kinds: a package, a plugin, a website, and more screen time. Each maps to one root-run fulfillment script with validated arguments. Nothing runs a string the child typed.
- The queue is files under `/var/lib/omarchy/kids/`, root-owned. The child writes into a sticky spool the way `at` and mail do; a root oneshot moves valid requests into the queue. No daemon, no root socket, no long-lived process parsing child input.
- The parent's phone is the first way to answer. It runs a small web app served by the child's machine, from files in the Omarchy package, over the parent's tailnet. The phone holds an Ed25519 key. A decision is a signature over the request. Root verifies it against a public key the parent enrolled as root.
- The buzz is web push, sent by the machine straight to the phone's push service. The payload is encrypted to the phone and carries the whole request, so the phone shows what was asked even when it cannot reach the machine.
- When the phone cannot reach the machine, it shows a six-digit code bound to that one request and that one decision. The parent says it; the child types it. Root checks it. It is a receipt for a decision made on the phone, not a password.
- At the keyboard, approval is being root. `omarchy kids approve` runs through the same `require_root` shape as `bin/omarchy-dns`: `sudo` in a terminal, `pkexec` without one. The parent's account password is the credential. The parent's own session gets a toast; `ssh` works with the same command.
- No relay in core. Not a stranger's, not the project's. The machine is the origin; the tailnet carries the bytes; the package carries the code.
- No surveillance. The queue holds what the child asked for and what the parent answered. Nothing else is recorded, on the machine or on the phone.

## Threat model

- **The child cannot forge an approval.** Fulfillment runs only as root, from one of three things: the parent's password entered interactively, a decision signed by a key the parent enrolled as root, or a code derived from a secret that only root and the phone hold. Nothing under the child's home or in the child's session is trusted. The handler that talks to the phone runs as an unprivileged system user and can only write files into a spool that root verifies.
- **The child cannot change a request after the parent reads it.** The spool copy the child wrote is consumed and discarded by the root dispatcher. The phone signs over a hash of the queue record; root recomputes that hash from its own copy. A decision for one request cannot be moved to another, and a decision for one machine cannot be replayed on another, because the request id and the machine's host id are in the signed bytes.
- **The child cannot smuggle a command through a request.** Request kinds are an enum. Arguments are validated by kind (a package name, a git URL passed through `omarchy-git-url-check`, a domain, a minute count) and passed as argv to fixed scripts. There is no `sh -c` anywhere in the path. Root scripts pin `PATH` the way `omarchy-dns` does.
- **The child cannot pester.** The dispatcher keeps one pending request per child per kind, refuses a repeat of a rejected request for a day, and caps requests per hour. The phone gets one push when a request is filed and one when it is decided. Nothing else buzzes.
- **The child cannot pair a phone.** Pairing ends with the parent typing, as root, the six digits the phone shows. The digits are derived from the phone's key, so a substituted key changes them. A child who scans the pairing QR with their own phone offers a key that root never accepts, because the parent is looking at a different phone.
- **The child cannot guess a code.** Six digits, three attempts, then the request is voided and a new one is needed, and new requests are rate-limited. The code is single-use and only valid for the decision the parent made.
- **The parent's password stays with the parent.** The phone path never types it anywhere. The local pkexec path types it at the child's keyboard; the manual says so and points at the phone.
- **The network is not trusted, and it is not the trust root.** Phone and machine talk over the parent's tailnet, under TLS with a certificate Tailscale issues for the machine's tailnet name. Tailscale holds no signing key and cannot approve anything. A rogue node on the tailnet could read pending asks and the history of asks, and could hammer the handler; it cannot approve, deny, pair, or subscribe, because every call except the pairing offer is signed by an enrolled phone. The push service (Apple's or Google's) sees ciphertext and timing.
- **The code the phone runs is the code DHH signed.** The web app is static files under `$OMARCHY_PATH/default/kids/phone/`, root-owned, out of the package, served by the machine. No CDN, no third-party script. Signing uses WebCrypto Ed25519 with a non-extractable key, so a script on the origin cannot read the key out; it could only sign while the page is open, and the page comes from the package.
- **Not covered.** A child with the parent's unlocked phone; the phone's lock is the control there, the same as Ask to Buy. A compromised parent account. Anything that already has root. A Tailscale control plane that adds a node to the tailnet: it can read, it cannot approve. Same boundaries as `plans/kids.md`.

## Rejected approaches

- **A root daemon with a socket.** [omarchy-parentapproval](https://github.com/aphexddb/omarchy-parentapproval)'s core (`internal/daemon/daemon.go`, a `0666` unix socket into a root process parsing child input). A spool directory plus a path-triggered oneshot gives the same queue with no long-lived root process and no listener. The only listener added is a systemd socket on `127.0.0.1` that starts an unprivileged, per-connection process for the phone; root never reads a byte from the network.
- **Approving command strings.** The experiment shows the parent a shell line and then runs it with `sh -c` as root. A parent reading `pacman -U ./pkg.tar.zst` on a phone cannot know what is in the file. Intents with fixed fulfillment instead.
- **Granting the child sudo and gating it with PAM.** The experiment writes `%omarchy-kids ALL=(ALL:ALL) ALL` to sudoers and relies on a patched PAM stack to demand the phone. That inverts the one rule: the parent is in `wheel`, the child is not. The child keeps no sudo; approval never passes through the child's `sudo`.
- **A relay that serves the phone's code, run by anyone but the parent.** The experiment's `docs/trust-model.md`: the relay operator can forge an allow by serving hostile JavaScript, because the relay is where the key-holding code comes from. Hosting it at `parentapprovals.com` or at an Omarchy project domain changes who, not what. A project relay would also make DHH the operator of a service every family's approvals pass through, with uptime, VAPID keys, and push subscriptions to keep. The child's machine is the origin instead: it already holds the root-owned queue, the parent's tailnet already reaches it, and the package already carries the code.
- **A self-hosted relay shipped as an optional Omarchy service.** On the machine itself, a relay is the machine serving. On another tailnet node it adds a hop, a second place to keep state, and a second thing to pair.
- **Local network only, with mDNS.** `avahi` and `nss-mdns` are in the base packages, so `kidbox.local` resolves. No public certificate for a `.local` name means no secure context on the phone, so no service worker, no push, and no Home Screen app on iOS. It also means an inbound port on every Wi-Fi the laptop joins, against `ufw default deny incoming` in `install/config/firewall.sh`. Everything the LAN offers, the tailnet offers on the same Wi-Fi and in the kitchen.
- **Web push alone, with no path back.** Push is the buzz, but it is one-way, and the phone needs an origin to subscribe from and to pair with at least once. Push is the notification leg, not the transport.
- **A QR or typed code as the primary path.** It needs someone at the child's screen for every decision, which is the walk-over with extra steps. It is the fallback for when the phone has no path to the machine.
- **A parent PIN.** A four-to-six digit PIN typed on the child's screen is a second credential: reusable, brute-forceable unless root rate-limits it, and a new mode for the shell's polkit agent. The code is not a PIN. It is single-use, bound to one request and one decision, derived from a secret the child never sees, and dead after three attempts. The parent decides on the phone; the code only carries the decision across the room.
- **A setuid helper for writing requests.** A sticky spool does the same job with kernel-enforced ownership and no privileged code parsing child input on the write side.
- **Email, SMS, or third-party push services in core.** Web push is the notification, and it goes from the machine to the phone's own push service. The parent's notifier runs an `omarchy-hook` so a parent who wants ntfy or a Pushover script can wire it in one line.
- **Tailscale Funnel.** It would put the origin on the public internet so a phone without Tailscale could reach it. The origin serves the request history and accepts pairing offers; it stays on the tailnet.
- **A vendored crypto library in the web app.** The experiment ships `nacl.min.js` and `sha256.min.js` with subresource-integrity pins (`docs/web-assets.md`). WebCrypto has Ed25519 and SHA-256 in Safari 17 and current Chrome. No third-party JavaScript to vouch for.
- **A time-window unlock token.** A window unlocks every plugin for N minutes, including ones the parent never saw. The token is per URL.

## What it looks like

Setup. `omarchy-setup-kids` (or first boot for a Child install) creates the child, then asks "Add a parent's phone?" If Tailscale is not installed it runs `omarchy-install-service-tailscale`, which signs the machine in from the browser. Then `omarchy-kids-phone add` prints a QR code and the address underneath it, `https://kidbox.tail1234.ts.net/pair/KJ74QPX2`, with the line "Scan with the parent's phone, not the child's." The parent installs Tailscale on their phone from the store, signs in to the same account, and scans. The page asks "Name this phone", the parent types "Anna's iPhone" and taps Pair. On an iPhone the page first says to add it to the Home Screen and open the icon, and shows the same eight-character code to type there, because the key has to be born in the app that will keep it. The phone shows six digits. The terminal says "Anna's iPhone offered a key. Type the six digits it shows." The parent types them. "Paired Anna's iPhone. Tap Allow notifications on the phone." The terminal waits, then prints "Notifications on. Anna's iPhone will buzz when Milo asks for something." Setup continues.

First request. Milo opens the kids menu, picks Ask a parent, then App, and picks tuxpaint from the list. Milo's screen dims to an overlay: "MILO ASKS TO INSTALL tuxpaint", a match code "4 7 2", and "Waiting for a parent. This will keep waiting if you close it." A small glyph sits in the bar. In the kitchen, Anna's phone buzzes: "Milo asks to install tuxpaint". She taps it. The screen says "Milo's computer" across the top, "Install tuxpaint" in large type, "Milo · match 472 · asked 1 minute ago", and two buttons, Deny and Approve. She taps Approve. The phone says "Approved. Installing on Milo's computer." Milo's overlay flashes a green check, "Anna said yes", and the install runs. The bar glyph goes away.

Denying with a reason. Anna taps Deny. The phone offers a line for a reason and a few one-tap ones: "Not today", "Let's talk first", "Not for your age". She picks one or types her own and taps Deny. Milo's overlay flashes a red cross and "Anna said no: not today." Asking for the same thing again is refused for a day, and the overlay says so.

Pending and past. Anna opens the app when nothing is buzzing. It lists each computer she is a parent on. Under "Milo's computer" she sees what is pending, if anything, each with the same Approve and Deny buttons, and below that the last thirty days: "tuxpaint · approved by Anna · Tuesday", "minecraft.net · denied by Ben · Monday", "30 more minutes · expired · Sunday". That is the whole history. It is a history of asks and answers, not of what Milo did.

Second parent. Ben runs `omarchy kids phone add` from his own account on the machine and pairs his phone the same way. Both phones buzz for every request. Whoever taps first decides. The other phone's notification is replaced by "Anna approved Milo's request: tuxpaint", so nobody answers a question that is already answered.

Lost phone. `omarchy kids phone list` shows "Anna's iPhone · added 2 March · last buzzed today" and "Ben's Pixel · added 2 March · notifications off since 14 April". `sudo omarchy kids phone remove "Anna's iPhone"` drops its key; any decision signed by it is refused from that moment. Anna pairs her new phone with `add`. On a phone, "Forget this computer" clears the key locally. That is a convenience, not a revocation; revocation is the command on the machine, run as root.

Phone with no path to the machine. Anna is at work with Tailscale off, or the family never set up a tailnet after pairing on a friend's. The push still arrives, because it only needs the machine's own internet connection. She taps Approve. The phone tries the machine, cannot reach it, and says "Can't reach Milo's computer. Read this code to Milo, or type it on his screen: 8 2 3 1 5 0. Turn on Tailscale to approve with one tap next time." Milo types it into the overlay, or runs `omarchy kids code 823150`. Green check. Deny needs no code; the request expires on its own, or Milo withdraws it. Three wrong codes void the request, and Milo is told to ask again.

No phone at all. The family skipped the phone, or the machine is offline. At the keyboard, the parent runs `omarchy kids approve` in Milo's terminal and pkexec asks for their password. In their own session, a critical toast says "Milo asks to install tuxpaint" and clicking it opens a floating terminal running `omarchy kids approve <id>`, which asks `sudo` for their password. From a laptop, `ssh kidbox omarchy kids approve`. Same command, same password prompt.

Child in a terminal. `omarchy plugin add https://…` in a kids session refuses and prints `Ask a parent: omarchy kids ask plugin https://…`. `omarchy kids ask package tuxpaint` files the request and waits, or returns at once with `--no-wait`. `omarchy kids requests` shows the child their own pending and answered asks.

## Design

### Request kinds

Each kind names its argument validation and the fulfillment script that runs as root.

| Kind | Argument | Validation | Fulfillment |
|---|---|---|---|
| `package` | package name | `[a-z0-9@._+-]+`, present in the configured repos (`pacman -Si`) | `omarchy-pkg-add <name>` |
| `plugin` | git URL | `omarchy-git-url-check`, then a clone into a root-owned staging dir and `omarchy-plugin-validate` | mint the per-URL unlock token, then `runuser -u <child> -- omarchy-plugin-add --yes <url>` |
| `domain` | hostname | RFC 1123 label syntax, no scheme or path | `omarchy-kids-allow <domain>` from `plans/kids.md` |
| `time` | minutes | integer, at most `max_extension` in `/etc/omarchy/kids/screen-time.conf` | the extension path of `omarchy-kids-screentime` from `plans/kids.md` |

AUR packages are refused at validation in the first version. Building an AUR package on a kids machine because a child asked is not something the parent can evaluate from a name on a phone.

Settings changes beyond these four are not a request kind. The parent changes the allowlist, budget, DNS tier, and plugin set from their own account with the commands in `plans/kids.md`. A generic "change setting X" request is a command string with a different name.

### State

All under `/var/lib/omarchy/kids/`, created by `etc/tmpfiles.d/omarchy-kids.conf` and by `omarchy-kids-apply`, so both fresh installs and existing installs get them. Two system users come from `etc/sysusers.d/omarchy-kids.conf`: the `omarchy-kids` group from `plans/kids.md`, and `omarchy-kids-phone`, the unprivileged user the phone handler and the push sender run as.

- `spool/` — `1730 root:omarchy-kids`. The child's `omarchy-kids-ask` writes `<epoch>-<random>.json` here. The owner uid of the file is the child's identity; the file body is untrusted. A spool record is either an ask or a note on an existing ask: a withdrawal, or a typed code. Notes are honoured only from the ask's own uid.
- `queue/` — `0755 root`, files `0644 root`. Validated pending requests, one JSON file per request named by id. Both sides read it; nobody but root writes it.
- `decided/` — `0755 root`, files `0644 root`. Finished requests with `result`, `decided_by`, `decided_at`, `reason`, and the fulfillment exit status. Pruned after 30 days by the same tmpfiles rule. This is the whole history, on the machine and on the phone.
- `decisions/` — `1730 root:omarchy-kids-phone`. The phone handler writes `<id>.<device>.json` here: the decision, the signature, and an optional reason. Anything may land here; only a valid signature does anything.
- `unlock/<child>/<sha256 of url>` — `0644 root`. The per-request plugin token `omarchy-plugin-add` looks for in a kids session.
- `phone/` — `0700 omarchy-kids-phone`. The handler's own state, none of it a trust root: `pair/` for pairing sessions in flight, `subs/<device>.json` for push subscriptions, `vapid.pem` for the push sender's VAPID key. The child cannot read it; root does not need to.

Trust roots live in `/etc/omarchy/kids/`, root-owned:

- `approvers/<name>.pub` — `0644`. The phone's Ed25519 public key, PEM. Readable so the handler can check signatures before root does.
- `approvers/<name>.secret` — `0600`. The 32-byte secret the offline code is derived from. Only root reads it.
- `host-id` — `0644`. Random, minted by `omarchy-kids-apply`, in every signed decision so a decision cannot be replayed against another machine.

A request record:

```json
{"id":"1788200000-3f9a","kind":"package","arg":"tuxpaint","user":"milo","uid":1001,"match":"472","asked_at":1788200000,"expires_at":1788286400}
```

Requests expire after a day. The dispatcher moves expired queue entries to `decided/` with `result: expired`. `match` is three random digits shown on the child's screen and on the phone, so a parent and a child in different rooms can be sure they are talking about the same request.

### Asking: `omarchy-kids-ask`

- Runs as the child. Refuses unless `omarchy-kids-active` succeeds; a parent has no reason to ask themselves.
- `omarchy-kids-ask <kind> <arg>` writes the spool file and prints the id. `-i` runs the gum flow the menu uses. `--wait` blocks until a decision lands in `decided/`, which the terminal form of the plugin refusal uses so the install continues in place.
- Every ask also summons the child's overlay through `omarchy-shell shell summon omarchy.kids-ask`, with the id in the payload.
- `omarchy-kids-ask --withdraw <id>` and `omarchy-kids-code <id> <digits>` write notes into the same spool. The spool write is the only thing the child does. Everything after is root.

### Dispatching: `omarchy-kids-dispatch`

- Root oneshot, `omarchy-kids-dispatch.service`, started by `omarchy-kids-dispatch.path` with `DirectoryNotEmpty=` on `spool/` and on `decisions/`. Both are system units shipped under `etc/systemd/system/` and enabled by `omarchy-kids-apply`.
- For each spool file: check the owner uid is in `omarchy-kids`; parse with `jq` against the fixed schema; validate the argument for its kind by calling `omarchy-kids-request-check`; apply the rate rules. Valid requests are rewritten from the parsed fields, never copied, into `queue/` with `user` and `uid` taken from the file owner, not the body. Invalid ones are logged to the journal and dropped. A withdrawal moves the child's own request to `decided/` with `result: withdrawn`. A code is checked as described under "The code".
- For each decision file: run `omarchy-kids-decision-check`, which rebuilds the canonical bytes from the queue record and verifies the signature with `openssl pkeyutl -verify -rawin` against every key in `approvers/`. A valid `allow` calls `omarchy-kids-fulfill`; a valid `deny` moves the record with the reason. `decided_by` is the approver's name. Invalid files are dropped and counted; more than a handful in a minute is logged as a warning, because it means something on the tailnet is misbehaving.
- `omarchy-kids-request-check <file>` and `omarchy-kids-decision-check <request> <decision>` are the pure parts: schema, kind enum, argument syntax, rate rules, canonical bytes, signature. They take no privileges and are what the shell tests exercise.
- The dispatcher also expires stale queue entries, so the path unit is the only timer this feature needs.

### Deciding at the keyboard: `omarchy-kids-approve` and `omarchy-kids-reject`

- `omarchy-kids-approve [id]` follows `require_root` from `bin/omarchy-dns`: `sudo` when there is a terminal, `pkexec` when there is not, re-executing the packaged `/usr/bin/omarchy-kids-approve`. There is no sudoers `NOPASSWD` grant: the password prompt is the authentication. `test/shell.d/kids-approve-test.sh` asserts no `etc/sudoers.d/omarchy-kids*` file names it.
- With no id it lists the queue in gum and lets the parent pick. With an id it prints the record and asks for confirmation. `--yes` skips the confirm for scripted use over ssh.
- On yes it calls `omarchy-kids-fulfill <queue-file>`, which dispatches on kind to the fulfillment column above, then moves the record to `decided/` with the result and `decided_by` set to `$SUDO_USER` or the pkexec caller. On failure the record is decided with the exit status and the parent sees the output.
- `omarchy-kids-reject [id] [reason]` is the same shape and only moves the record. The reason, if given, is shown to the child. Named `reject` because `omarchy-kids-deny` is the allowlist command in `plans/kids.md`.
- Both carry `# omarchy:requires-sudo=true`.

### The phone app

- Static files under `default/kids/phone/`: `index.html`, `app.js`, `app.css`, `sw.js`, `manifest.webmanifest`, and two icons. No build step, no framework, no third-party script. Served by the machine, so the origin is `https://<machine>.<tailnet>.ts.net`.
- The key is generated with `crypto.subtle.generateKey({name: "Ed25519"}, false, ["sign"])` and stored as a non-extractable `CryptoKey` in IndexedDB, one per paired computer. The secret is never readable by script.
- Screens, in the order a parent meets them: Pair (name this phone), Same code? (the six digits, Abort and Confirm), Allow notifications (with the Add to Home Screen step first on iOS), Home (each computer, its pending asks with Approve and Deny, its last thirty days), Approve (computer, the ask in one line, child and match code, how long ago, Deny and Approve), Reason (free text and three one-tap reasons), Code (the six digits when the machine is unreachable), and Forget this computer.
- While the app is open it long-polls `GET /api/watch` with a signed nonce, so a request filed while the parent is already looking appears at once without a push.
- Every call except the pairing offer carries a signature from the phone's key over a purpose-prefixed line format: `OMARCHY-WATCH/1`, `OMARCHY-SUB/1`, `OMARCHY-APPROVE/1`. The handler checks it; root checks the one that matters again.

### Pairing: `omarchy-kids-phone`

- `omarchy-kids-phone add` runs as root through `require_root`. It needs a terminal, because the parent types six digits into it; from the menu it runs in `omarchy-launch-floating-terminal-with-presentation`.
- It checks that Tailscale is up and that HTTPS is enabled for the tailnet; if not, it prints the one admin-console step and opens the Tailscale webapp `omarchy-install-service-tailscale` installs. It then makes sure `tailscale serve` is configured (below) and that `ufw` allows 443 in on `tailscale0`, and only there.
- It mints an eight-character pairing code, writes `phone/pair/<code>.open` with a ten-minute expiry, and prints the pairing URL as a QR with `qrencode -t ANSIUTF8` and as text. The code is short so an iPhone parent can type it inside the Home Screen app, where the key must be created; Android Chrome pairs straight from the scanned URL.
- The phone posts its name, its public key, and a fresh 32-byte code secret to `POST /api/pair/<code>`. The handler accepts it only while `<code>.open` exists and no offer has been made, and writes `<code>.offer`. Two offers for one code is a failure, not a swap.
- Root reads the offer, computes the six digits the way the experiment's `protocol.PairSAS` does (`OMARCHY-SAS/1`, the code, the public key, SHA-256, six decimal digits), shows the phone's name, and asks the parent to type the digits from the phone. A bare Enter does not enroll. On a match it writes `approvers/<name>.pub`, `approvers/<name>.secret`, and `<code>.done`, which the phone's long-poll on `GET /api/pair/<code>/wait` returns together with the host name, the host id, and the VAPID public key.
- The phone then asks for notification permission and posts its push subscription, signed, to `POST /api/subscribe`. Root waits for `phone/subs/<device>.json` to appear, prints that notifications are on, and cleans up the pairing files. If the parent gives up before that, pairing is still done; `list` shows notifications off, and opening the app later finishes it.
- `omarchy-kids-phone list` prints every approver with its name, the date added, and when it was last pushed successfully. `omarchy-kids-phone remove <name>` (root) deletes the key, the secret, and the subscription. `add` and `remove` carry `# omarchy:requires-sudo=true`.

### Reaching the machine

- Transport is the parent's tailnet. `omarchy-install-service-tailscale` is the project's existing path to "reach this machine from elsewhere", and `plans/remote.md` builds on the same thing. The phone needs the Tailscale app and the same account; that is one install and one sign-in, once.
- `tailscale serve` terminates TLS with a certificate Tailscale issues for the machine's name, serves `$OMARCHY_PATH/default/kids/phone/` as static files at `/`, and proxies `/api` to `127.0.0.1:17421`. The serve configuration is persistent in tailscaled; `omarchy-kids-phone add` sets it and `omarchy-kids-remove` clears it. Funnel is never enabled.
- `127.0.0.1:17421` is `omarchy-kids-phone.socket`, a systemd socket with `Accept=yes` that starts one `omarchy-kids-phone@.service` per connection with `User=omarchy-kids-phone` and the connection on stdin. Nothing runs between connections. `MaxConnections=` keeps a misbehaving node from forking the machine to death.
- The per-connection process is `omarchy-kids-phone-serve`, a hidden command written in Ruby using only the standard library: `OpenSSL::PKey` for Ed25519 verification, `JSON`, nothing else. Ruby is in `install/omarchy-base.packages`. It reads one HTTP request, handles the routes below, and exits. It can read `queue/`, `decided/`, and `approvers/*.pub`; it can write only `decisions/` and its own `phone/`. It holds no key and is not a trust root.
- Routes: `POST /api/pair/<code>`, `GET /api/pair/<code>/wait`, `POST /api/subscribe`, `GET /api/requests` (pending and the last thirty days, for the phone's Home screen), `GET /api/watch`, `POST /api/decide/<id>`. The last four require a valid signature from an enrolled phone; the pairing routes require an open pairing code.

### Telling the phone: `omarchy-kids-push`

- `omarchy-kids-push.path` watches `queue/` and `decided/`; `omarchy-kids-push.service` runs `omarchy-kids-push` as `omarchy-kids-phone`. It sends one push per new queue record and one per new decided record to every subscription in `phone/subs/`. The unit tracks what it has sent under `phone/sent/`.
- `omarchy-kids-push` is the second Ruby script, standard library only: `OpenSSL` for the VAPID ES256 token and for the RFC 8291 payload encryption (ECDH on P-256, HKDF, AES-128-GCM), `Net::HTTP` to post to the push endpoint. It generates `phone/vapid.pem` on first run. The `openssl` command line cannot do AES-GCM, so this is Ruby and not bash.
- The payload is the request record plus the host name, encrypted to the phone's subscription keys. The push service sees ciphertext. The notification can say "Milo asks to install tuxpaint", and the app can show the request without fetching anything.
- The service worker caches the app shell at install, shows the notification when no window is visible, and hands the payload to an open window otherwise. Tapping the notification opens the Approve screen from the payload.
- A push endpoint that answers 404 or 410 is marked dead in `phone/subs/`; `omarchy-kids-phone list` shows it as notifications off. The app re-subscribes when opened.

### Signed decisions

- Canonical decision bytes, one field per line with a trailing newline after every line, in the style of the experiment's `OMARCHY-APPROVE/1`: the version tag, the decision (`allow` or `deny`), the request id, the host id, the SHA-256 of the queue record's canonical fields (`id`, `kind`, `arg`, `user`, `uid`, `asked_at`), and an expiry at most ten minutes ahead. Ed25519 over those bytes.
- The phone rebuilds the record hash from the fields it displayed and refuses to sign if it differs from the hash the machine sent. Root rebuilds the bytes from its own queue copy and never from the decision file, so a decision cannot be retargeted.
- `POST /api/decide/<id>` writes `decisions/<id>.<device>.json` holding the device name, the decision, the signature, and the reason. The reason is outside the signature; it is a note to the child, and an unsigned `deny` is harmless. The path unit wakes the dispatcher.
- The first valid decision wins. Later ones for the same id are dropped, and the other phones get the decided push so their notifications are replaced.
- An unsigned `deny` from the request's own uid, through the spool as a withdrawal, is honoured so a child can take an ask back.

### The code

- For when the phone cannot reach the machine. The phone derives the code from the secret it generated at pairing: six decimal digits from HMAC-SHA256 over `OMARCHY-CODE/1`, the request id, and `allow`. The phone shows it only after a decision fails to post.
- The child types it in the overlay, or runs `omarchy kids code <digits>`, which writes a note into the spool with the pending request's id. The dispatcher recomputes the code with every `.secret` in `approvers/` and fulfills on a match, with `decided_by` set to that approver.
- Three misses void the request (`result: voided`) and the child is told to ask again. New requests are already rate-limited, so guessing is not a strategy. Deny has no code.

### Telling the parent's session

- `omarchy-kids-notify.path` and `.service` are user units in `default/systemd/user/`, enabled with the others in `install/user/first-run/enable-user-units.sh`. The path unit watches `queue/` and `decided/`. The service runs `omarchy-kids-notify`, which exits at once unless the user is in `wheel`.
- For each new queue file it has not announced (tracked under `~/.local/state/omarchy/kids/announced/`), it sends `omarchy-notification-send -u critical -g <glyph> "Milo asks to install tuxpaint" --exec omarchy-launch-floating-terminal-with-presentation omarchy-kids-approve <id>`. Critical so it does not expire; `--exec` so the click survives a shell restart, per `docs/notifications.md`. When the record is decided, by a phone or by anyone, it dismisses that toast with `omarchy-notification-dismiss`.
- It then runs `omarchy-hook kids-request <queue-file>`. That is the extension point for a parent who wants the request forwarded somewhere else.
- The parent's menu gains `kids.requests`, "Kids > Requests", guarded by `when: ! omarchy-kids-active && omarchy-kids-pending`, running the same floating terminal, and `kids.phone`, "Kids > Add a parent's phone", running `omarchy-kids-phone add` in one. `omarchy-kids-pending` is a hidden predicate that exits 0 when `queue/` is non-empty.

### Telling the child

- An `overlay` plugin, `shell/plugins/kids-ask/Panel.qml`, modelled on the experiment's `overlay/Panel.qml`: who asks and for what across the top, the match code in large type, a waiting line, a verdict animation (green check or red cross with the parent's name and reason), and a six-box code entry that appears when the child taps "I have a code". It is summoned by `omarchy-kids-ask` and reads the request's state from `queue/` and `decided/` with a `FileView`; there is no IPC to add. Escape closes it; the request keeps waiting.
- The same `omarchy-kids-notify` user unit runs in the child's session, where `omarchy-kids-active` succeeds, and instead watches `decided/`. It toasts the result with a plain sentence and no click action, for when the overlay was closed.
- A bar glyph, shipped with the shell and guarded by `omarchy-kids-active`, shows while any queue file belongs to the current uid. Clicking it summons the overlay for the oldest one.

### Menu

- In the kids submenu from `plans/kids.md`: `kids.ask`, "Ask a parent", with children `kids.ask.app`, `kids.ask.website`, `kids.ask.time`, each running `omarchy-launch-floating-terminal-with-presentation omarchy-kids-ask -i <kind>`. Plugin asks come from the terminal refusal path rather than a menu entry, since a child rarely has a git URL in hand.
- Guards use `omarchy-kids-active` and `omarchy-kids-pending`. Once either is read by more than one row it goes into `GUARD_READERS` in `MenuModel.js`, as `docs/menu.md` requires, and `test/shell.d/menu-guards-test.sh` enforces it.
- No aliases.

### The plugin token

- `omarchy-plugin-add` in a kids session looks for `/var/lib/omarchy/kids/unlock/<user>/<sha256 of url>` and refuses without it. The fulfillment script writes that file just before running the install as the child, and removes it after.
- `omarchy kids unlock <url>` mints the same file for the parent-at-keyboard case. There is no time-window form.

### Command group

- Group `kids`, declared in `GROUP_DESCRIPTIONS` in `bin/omarchy` by `plans/kids.md`.
- User-facing: `omarchy-kids-ask`, `omarchy-kids-requests`, `omarchy-kids-approve`, `omarchy-kids-reject`, `omarchy-kids-phone` (`add`, `remove`, `list`), `omarchy-kids-code`.
- Hidden: `omarchy-kids-dispatch`, `omarchy-kids-fulfill`, `omarchy-kids-request-check`, `omarchy-kids-decision-check`, `omarchy-kids-notify`, `omarchy-kids-pending`, `omarchy-kids-phone-serve`, `omarchy-kids-push`.
- Privileged commands follow the sudo/pkexec rule in `default/agents/skills/omarchy/SKILL.md` and carry `# omarchy:requires-sudo=true`. `omarchy-kids-phone-serve` and `omarchy-kids-push` are the first Ruby in `bin/`; they carry the same metadata comments as everything else and `omarchy commands --check` lints them.

### Tests

- `test/shell.d/kids-request-check-test.sh` — schema, kind enum, argument syntax per kind, rate rules, expiry, all against fixture directories under `test/shell.d/fixtures/kids/`. This is the bulk of the logic and needs no root.
- `test/shell.d/kids-decision-check-test.sh` — canonical bytes match a fixture signed with a fixture key, a decision for another id or another host id fails, an expired decision fails, a second key from `approvers/` verifies, a removed key does not, the code matches for `allow` and only for the right id, three misses void.
- `test/shell.d/kids-ask-test.sh` — refuses outside a kids session (stub `omarchy-kids-active`), writes a record whose body carries no `user` field the dispatcher would trust, `--wait` returns on a decided file, a withdrawal note names the right id.
- `test/shell.d/kids-approve-test.sh` — the `require_root` shape matches `omarchy-dns` (`PACKAGED_PATH`, `sudo` with a tty, `pkexec` without), no sudoers grant names it, `--yes` is honoured, reject moves without fulfilling.
- `test/shell.d/kids-phone-test.sh` — the pairing digits match the experiment's `protocol.PairSAS` vectors for the same inputs, a second offer for one code is refused, an offer for a closed code is refused, `add` enrolls nothing on a wrong six digits, `remove` deletes all three files.
- `test/shell.d/kids-phone-serve-test.sh` — run with a request on stdin: unsigned `decide` is 401 and writes nothing, signed `decide` writes exactly one file with the right name, `requests` never returns anything outside `queue/` and `decided/`, a body over the limit is 413.
- `test/shell.d/kids-push-test.sh` — the VAPID token verifies with the public key, the payload decrypts with fixture subscription keys to the record, 410 marks the subscription dead. Run with `Net::HTTP` stubbed; nothing is sent.
- `test/shell.d/kids-notify-test.sh` — the parent path exits for non-wheel, the child path exits for wheel, the `--exec` argv is discrete words, the hook is called with the record path, a decided record dismisses the toast.
- `test/shell.d/menu-guards-test.sh` — the new readers are in `GUARD_READERS`.
- `./test/cli` — metadata lint on the new commands via `omarchy commands --check`.
- Acceptance, under `test/acceptance.d/`: a child session files a package request, the overlay shows it, a second session as the parent gets the toast, approves in the terminal, and the package is installed; the same for a plugin, which also proves the per-URL token; a decision file signed with a fixture key dropped into `decisions/` fulfills a request, and one signed with an unenrolled key does not. Dispatcher and fulfillment are exercised for real only here. The phone app is exercised in a browser by hand; see open questions.

### Migration

- Machines set up by `omarchy-setup-kids` before this ships lack the directories, the system units, the `omarchy-kids-phone` user, and the user units. `migrations/<epoch>.sh` no-ops unless `getent group omarchy-kids` succeeds, then runs `systemd-sysusers` and `systemd-tmpfiles --create` for the two new files and enables `omarchy-kids-dispatch.path`, `omarchy-kids-push.path`, and `omarchy-kids-phone.socket` through `sudo` or `pkexec` per the privilege rule, and enables the `omarchy-kids-notify` user units for the current user. It is idempotent so the second user's run finds the machine-wide steps done.
- It does not touch Tailscale or `tailscale serve`; that happens the first time a parent runs `omarchy kids phone add`, and the migration prints that this is available.
- If a time-window token shipped first, the same migration removes any leftover window file and prints that `omarchy kids unlock` now takes a URL.
- Fresh installs need no migration: `omarchy-kids-apply` does all of it.

## Evaluation of omarchy-parentapproval

The experiment at [github.com/aphexddb/omarchy-parentapproval](https://github.com/aphexddb/omarchy-parentapproval) is a Go daemon, a phone PWA, a relay server, packaging, a Quickshell overlay, and an agent skill. It does what its README says: a paired phone approves the child's `sudo` and `pkexec`. It is well tested for what it is (`internal/daemon/daemon_test.go` covers replay, command swap, unpaired allow, and peer-credential spoofing). The parent experience is largely right; the machine side is not.

### What it does

- The child's `sudo` and polkit auth are rerouted through PAM to `parentapproval pam` (`packaging/parentapproval.pam`, `cmd/parentapproval/setup.go` `patchPAM`), which writes a request into a root daemon over `/run/parentapproval/pam.sock`.
- The daemon dials out over WSS to a relay, default `https://parentapprovals.com`, which web-pushes paired phones (`internal/daemon/relay.go`, `internal/relay/relay.go`).
- The phone shows the command and a match code and signs `allow` or `deny` with an Ed25519 key that never leaves the phone (`docs/SPEC.md`). The daemon verifies over the fields it stored (`internal/daemon/daemon.go` `handleDecision`) and runs the command as root with `sh -c` (`Exec`, around line 971).

### What it got right about the parent

The experiment treats the parent as someone with a phone, not someone with an account. Most of its parent-side choices carry over unchanged.

- **The premise.** The README's first paragraph is the kitchen and the meeting, and "you should not have to walk over". Correct.
- **Pairing is one scan and six digits.** `cmdPair` in `cmd/parentapproval/main.go` prints a QR in the terminal with `qrdisp.Box` and the text "Scan with the parent's phone — not the kid's", then prints the offering phone's name and the key-bound digits and refuses a bare confirm. The phone side (`web/index.html` `pair` and `pair-wait`, `web/app.js` `bootPair`) asks for a name and shows "Same code?" with Abort and Confirm. The digits come from `protocol.PairSAS` over the session id and the public key, so a swapped key changes them. Kept: the format, the phone name on screen, and the parent typing the digits at the machine.
- **Notifications are part of pairing, not an afterthought.** `waitForPush` keeps `pair` running until the phone has subscribed, and the pages `pair-done`, `notify-setup`, and `a2hs` walk an iPhone parent through Add to Home Screen, open the icon, tap Allow. Kept, and `omarchy kids phone list` reports notifications on or off the way `cmdStatus` does.
- **One tap, with the right facts on screen.** The `approve` section shows the host as an eyebrow, who asked and through which service, the match code in large type with "MATCH THE LAPTOP", the command, a countdown, and Deny and Approve. `bootApprove` recomputes the command hash before signing and disables both buttons on a mismatch. Kept: the layout and the hash check; the command line becomes an intent in one sentence.
- **The app is live while open.** `startWatch` and `watchOne` long-poll a signed `GET /v1/watch` so a request appears at once when the parent already has the app open; `web/sw.js` hands a push to a visible window instead of showing a second notification, and `notificationclick` focuses the existing window. Kept.
- **Every paired phone is a parent.** `sealAsk` seals each ask to every paired phone and `handleNotify` in the relay fans a push out to every subscription for the host. Two parents, one request, both buzz. Kept.
- **The child side is calm.** `overlay/Panel.qml` says who wants to run what, shows the match code, and plays a check or a cross when the verdict lands. It summons through `omarchy-shell shell summon` and denies through `omarchy-notification-send`, which is the right way in. The overlay above is modelled on it.
- **Trust is stated.** `docs/trust-model.md` has a table of who can forge an allow, who can see the command, and who can replace the phone's code, and names the relay operator as able to forge an allow.

What it does not give the parent:

- No reason on a deny. `decide("deny")` sends the decision and nothing else.
- No history. After a decision the phone shows `result` for two seconds and then `home`; a stale link shows `gone`. Nothing lists what was asked last week.
- No pending list. One outstanding request per user, and a new one cancels the old (`Create`, `byUser`), with a 120-second TTL (`protocol.DefaultAskTTL`, clamped at 180). That is a sudo timeout, not a parent's afternoon. A parent who does not answer within two minutes has to be asked again.
- No device management on the phone. The home screen lists hosts by name (`showIdle`); revocation is `cmdRevoke` on the machine only.
- The second parent is not told the first answered. Push goes out once, from `Create`; nothing is sent on a decision. The stale notification stays on the other phone.
- The push body is generic, "A privileged command is waiting for your approval" (`Create`), because the relay is a third party that must not see the command.

### How it authenticates the parent

- Pairing shows a QR; the phone generates the key and posts the public half; a six-digit code derived from the key is confirmed on both ends (`handlePairOffer`, `handlePairPhoneConfirm`). Pairing and revocation over the socket are refused to members of `omarchy-kids` by `SO_PEERCRED` (`authorizeAdminRPC`). This is sound.
- The trust root is the relay origin, not the key. `docs/trust-model.md` says it plainly: a relay operator "can forge an allow, by serving hostile JS". The default relay is run by the author. Self-hosting is offered, not required.
- The private key is stored as raw bytes in IndexedDB and, for Safari's partitioned storage, copied through a cookie (`writeBridge`, `readBridge`) and through the relay as a pairing handoff (`pairHandoff`). Script on the origin can read it. A non-extractable WebCrypto key cannot be read out, which is why pairing above happens inside the Home Screen app instead of moving the secret.

### Where it stores state

- `/var/lib/parentapproval/` (`StateDirectoryMode=0700`): `host.key`, `parents/<device>.json` `0600`, `pending.json` `0600` (`internal/store/store.go`, `writePendingLocked`). Root-only and fine.
- `/run/parentapproval/pam.sock` is `chmod 0666` on purpose (`daemon.go` line 240, `TestSocketWorldConnectable`). `/run/parentapproval/polkit-<uid>` holds the polkit action and cookie as a `0644` file (`cmd/parentapproval/polkit.go` `writePolkitTicket`), readable by every user.
- On the relay: VAPID keys, push subscriptions, pairing tokens, and on the Safari path the phone's pairing secret for the token's lifetime.

### Can the child tamper with it

- Not with the approval itself: the child cannot pair, cannot sign, cannot change a stored request, and `create` takes the user from the socket peer, not the body (`createUser`). The PAM helper pins production paths and ignores the environment (`cmdPam`). Good work.
- Yes with everything around it:
  - `packaging/omarchy-kids.sudoers` grants `%omarchy-kids ALL=(ALL:ALL) ALL`. The child's lack of root now depends on `/etc/pam.d/sudo` staying patched.
  - `sudo parentapproval disable` (`setup.go` `cmdDisable` → `removeHooks`) unpatches PAM but leaves that sudoers file and `50-parentapproval.rules` in place. Only `make uninstall` and package removal delete them (`Makefile` lines 76 to 78). After `disable`, the child's own password grants full `sudo` and self-authenticated polkit. This is the single worst finding.
  - `applyHooks` treats a failed patch of `/etc/pam.d/polkit-1` as a note, not an error (`setup.go` lines 62 to 64), while `packaging/50-parentapproval.rules` has already made every polkit action `AUTH_SELF` for the kids group. If the patch fails, pkexec accepts the child's password.
  - The PAM patcher rewrites `/etc/pam.d/sudo` and re-hoists itself above `auth sufficient` lines, because Omarchy's own `omarchy-setup-security-fingerprint` and `omarchy-setup-security-fido2` prepend there. Two scripts fighting for the top of a PAM file is not a stable arrangement.
  - The `exec` and `redeem` socket ops trust `req.User` from the body (`dispatch`, lines 459 to 465), unlike `create`. Any local process can spend a fresh grant. It cannot change what runs, so this is denial of the approval rather than escalation, but it shows the socket boundary is not uniformly enforced.
  - Any local user can `create` requests through the `0666` socket. The only limit is one outstanding per user (`Create`). The parent's phone is the thing that buzzes.
  - `POST /push/subscribe` on the relay is unsigned (`internal/relay/relay.go` `handleSubscribe`). Anyone who learns a device id and host id can attach a push subscription to a paired phone's slot.
  - `parentapproval-polkit.service` registers a second polkit agent in kids sessions alongside the shell's `omarchy.polkit`; whichever registers last owns the session's prompts. A race with shell startup, not a security hole, but it will be flaky.
- Approved commands run as root via `sh -c` with the daemon's environment plus `HOME`, `USER`, and `SUDO_USER` set to the child's, in the child's working directory (`Exec`). Any tool in the command that honours `$HOME` reads child-writable config as root. The parent approved the string, not that.

### What is reusable

- The parent experience listed above: pairing, the notification gate, the approve screen, the live watch, fan-out to every phone, and the child's overlay.
- The canonical signing format with purpose prefixes and the rule that the verifier rebuilds the message from stored fields. Adopted, with a host id added.
- Short-authentication-string pairing derived from the key, so a swapped key changes the digits. Adopted byte for byte so the test vectors carry over.
- Unsigned deny is accepted, unsigned allow never is.
- Identity from the kernel (`SO_PEERCRED`), which becomes file ownership in a sticky spool.
- The test matrix as a checklist for `kids-request-check-test.sh` and `kids-decision-check-test.sh`.

### What should be rejected and why

- The sudoers grant and the PAM rewriting. They contradict the one rule and fail open on `disable`.
- The root daemon and world-writable socket. A spool and a oneshot cover the need.
- Command-string approval and root `sh -c`. Wrong granularity for a parent to judge, and the environment handling makes it worse.
- The hosted relay as default and the `curl | bash` installer. A third party's origin cannot be in a release DHH signs. The machine is the origin instead.
- The secret-moving parts of the phone app: raw keys in IndexedDB, the cookie bridge, the Safari handoff through the relay. A non-extractable key born in the Home Screen app removes all three.
- The footprint: Go, a relay with Docker and Railway config, and an agent skill symlinked into six agent directories for every kid and the parent (`setup.go` `linkSkills`). Kids mode is accounts and root-owned files on a stock install. Two Ruby scripts from the standard library and a directory of static files is the footprint accepted here.

Verdict: the right parent experience on the wrong machine side. Keep the parent side nearly whole, keep the protocol ideas, keep the overlay, and build the machine side as a spool, a oneshot, and an unprivileged handler that root never trusts.

## Relationship to plans/kids.md

Differences from the parent plan, and what to change there:

- **Unlock token.** The parent plan's `omarchy kids unlock` is valid for a set number of minutes. Change it to take a git URL and mint `/var/lib/omarchy/kids/unlock/<child>/<sha256 of url>`, with `omarchy-plugin-add` looking for that file. A window unlocks every plugin for N minutes, including ones the parent never saw, and is habit-forming: the parent opens a window and walks away. Amend before step 7 ships.
- **Polkit identity chooser.** `shell/plugins/polkit/PolkitAgent.qml` takes a password and never picks an identity. From a non-wheel session, `auth_admin` offers the admin identities; the agent has to authenticate as one of them, not as the child, and has no chooser. Add to step 2 of the parent plan: a spike on what Quickshell's `PolkitFlow` selects by default, and an identity chooser if it selects the caller. The prompt should also show the action's message rather than the bare program path, so "Allow tuxpaint.org" reads as what it is.
- **Approval in the first release.** The parent plan says "No new approval system in the first version" and makes a richer flow conditional on the polkit prompt proving insufficient. Change: the queue and the phone ship alongside step 7 and are offered during `omarchy-setup-kids`, with the polkit prompt as the fallback. The polkit prompt requires the parent at the child's keyboard, and a control that requires that is one the parent stops using. The parent plan's "What it looks like" for the parent's desktop should mention the phone. Its "Multiple children" open question is answered: requests carry the child, and the phone shows them grouped by child.
- **`omarchy-kids-deny`.** The parent plan uses it for the allowlist. The negative decision here is `omarchy-kids-reject`. No change; noted so nobody renames one into the other.
- **Tailscale.** The parent plan does not mention it. Used here only through `omarchy-install-service-tailscale`, which exists. No change.

Everything else holds: the account model, `omarchy-kids-active`, `/etc/omarchy/kids/`, `omarchy-kids-apply`, the `kids` group, and the rejection of surveillance and of a root daemon.

## Rollout

Build order, each step its own PR, each usable on its own.

1. Prerequisites, shipped with the parent plan's steps 2 and 7: the polkit identity spike and chooser; the per-URL token; `omarchy-plugin-add` printing the ask hint in a kids session.
2. The queue: sysusers and tmpfiles rules, `omarchy-kids-ask`, `omarchy-kids-request-check`, `omarchy-kids-dispatch` with its path unit, `omarchy-kids-fulfill`, `omarchy-kids-approve`, `omarchy-kids-reject`, `omarchy-kids-requests`, the child's overlay and bar glyph. Shell tests and the migration. The keyboard and `ssh` paths work from here.
3. The phone: `omarchy-kids-decision-check` and signed decisions in the dispatcher, `omarchy-kids-phone` with pairing, the `omarchy-kids-phone.socket` handler and `tailscale serve` setup, the web app, `omarchy-kids-push`, the code path, and the "Add a parent's phone?" step in `omarchy-setup-kids`. Shell tests for every pure part and the acceptance scenario with a fixture-signed decision.
4. The parent's session and menu: `omarchy-kids-notify` and its user units, toast dismissal on decision, the `kids-request` hook, the parent's Requests and Add a phone entries, the child's Ask entries.

Steps 3 and 4 both depend on step 2 and not on each other; step 3 goes first because it is the one parents use. Step 1 now. Steps 2 and 3 as soon as the parent plan's step 2 is merged, so the phone is in the same release as the child account. Step 4 with them or shortly after. The experiment's author is the first reviewer of step 3, and the `docs/SPEC.md` test vectors for `OMARCHY-SAS/1` and `OMARCHY-APPROVE/1` verify against `omarchy-kids-decision-check` before it merges.

## Open questions

- **Testing the web app.** The pure parts of the machine side are covered in `test/shell.d/`, but `default/kids/phone/app.js` is only exercised by hand in a browser. The shell tests already run Node through `run_node_test` in `test/shell.d/base-test.sh`; the canonical-bytes and SAS functions in `app.js` can be loaded there and checked against the same vectors as the bash side. WebCrypto and IndexedDB cannot. Decide whether a headless browser in the acceptance VM is worth adding, or whether the vectors are enough.
- **HTTPS on the tailnet.** `tailscale serve` needs HTTPS certificates enabled for the tailnet in the admin console, once, by the tailnet owner. `omarchy-kids-phone add` can detect and explain it but not do it. Check whether Tailscale's API allows enabling it from the CLI on a fresh tailnet, so setup never sends a parent to a web console.
- **Ruby in `bin/`.** `omarchy-kids-phone-serve` and `omarchy-kids-push` would be the first Ruby scripts in the repo. Ruby is in the base packages and the standard library covers everything they need; the alternative for AES-GCM is a compiled helper. Confirm before step 3, and decide whether a `test/shell.d/` convention for Ruby tests is wanted or `ruby -e` inside bash tests is enough.
- **Waiting in place.** `omarchy-kids-ask --wait` leaves the child's terminal blocked on a parent who may be out. A day-long expiry is generous for the queue and absurd for a terminal. Proposed: `--wait` gives up after ten minutes and prints that the request is still filed and the overlay will show the answer.
- **Granting time unasked.** "Ten more minutes" will be the most frequent request, and on the phone it is one tap. Open: whether the parent should be able to grant time from the app's Home screen with no child ask behind it. That is a new request kind with the parent as the author; decide after real use.
- **Package requests and the menu.** A child does not know package names. The ask flow needs a search over `pacman -Ss` with a curated description, or a short list of kid-tagged packages next to the plugin list. Which one is a content question for the kids theme and plugin work.
- **Reading the history from the tailnet.** `GET /api/requests` returns thirty days of asks to any enrolled phone, and the queue itself is world-readable on the machine. Both are the same history the child sees on their own screen, so nothing is hidden from anyone in the family. Confirm this matches the no-surveillance line: the parent sees what was asked, never what was done.
- **Decisions spool quota.** Anything on the tailnet can write junk into `decisions/` through the handler, and only a valid signature acts. `MaxConnections=` and the handler's body limit bound it, and the dispatcher logs bursts. If that proves noisy, a per-device quota in the handler is the next step.
- **Two machines, one phone.** A family with two kids machines pairs the phone with each; the app lists both, and the host id keeps decisions apart. Push subscriptions are per-origin, so each machine sends its own. Whether the app should merge the two histories into one view is a design question for when it happens.
