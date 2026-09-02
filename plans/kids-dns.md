# Plan: Kids DNS — filtering tiers for the child's machine

Revision 1.

## Problem

`plans/kids.md` puts web access on two legs: a browser policy and a DNS filter. The browser policy only reaches browsers. Games, Electron apps, plugins, and anything the child runs from a terminal resolve names through the system resolver, and that resolver is whatever the machine owner picked in the network panel. Nothing stops a child from getting to a site the browser would have refused.

What exists today:

- `bin/omarchy-dns` writes NetworkManager global DNS to `/etc/NetworkManager/conf.d/20-omarchy-dns.conf`, pins every wired and Wi-Fi connection with `nmcli connection modify`, and rewrites `/etc/systemd/resolved.conf` wholesale. It knows Cloudflare, Google, DHCP, and Custom.
- `etc/sudoers.d/omarchy-dns` grants `%wheel` passwordless `omarchy-dns Cloudflare|Google|DHCP` so the network panel toggle does not stop for a password. Without a terminal and without the grant the script falls through to `pkexec`, a polkit prompt on screen.
- `install/helpers/browser-policy.sh` hardens the managed policy directories for Chromium, Chrome, Edge, and Brave, and installs `default/firefox/policies.json` into Firefox and Zen distribution directories. Every file in them is root-owned.

## Shape

- Three tiers, one root-owned file: `/etc/omarchy/kids/dns` holds `off`, `family`, or `allowlist`. `family` is the default for a kids machine.
- `family` is a new `Family` provider in `omarchy-dns`, pointing the machine at Cloudflare for Families. No daemon, no lists, no timer.
- `allowlist` runs dnsmasq on loopback with an allow-only configuration rendered from `/etc/omarchy/kids/allowlist`, the same file the browser URL allowlist is rendered from. Everything not on the list resolves to nothing.
- DNS is per machine. Both tiers apply to the parent's session too.
- Every file that carries a rule is root-owned, and every command that changes one is privileged (`plans/kids.md`). The child is not in `wheel`, so each attempt ends at a polkit prompt for the parent's password.
- No query log. A blocked name is diagnosed with a check command, not read out of a history.

## Rejected approaches

- **A local blocklist daemon as the first tier.** omarchy-pisafe built this. It needs a daemon, a list-refresh timer, third-party list data fetched daily, and its own privilege model, and it still needs the browser policy to stop DoH. The family upstream gives the same protection for the common case with none of that.
- **A blocklist tier at all.** The under-13 posture is an allowlist (`plans/kids.md`). A blocklist is "everything except what someone else flagged"; its content changes daily and nobody at Omarchy reviews it. Ad-blocking is a fine community package. It is not a kids feature.
- **Failing open to the network's DNS when the family resolver is unreachable.** pisafe does this (`upstream = auto`); for pisafe it is harmless because its upstream is unfiltered anyway. For a family upstream it silently removes the filter. The Family provider fails closed. The parent can switch to DHCP from the panel.
- **A second admin group.** pisafe adds `pisafe-admin` with its own sudoers rule, POSIX ACLs, and a polkit action. The parent is in `wheel`. Nothing here needs another group.
- **Per-user DNS.** Applications talk to systemd-resolved's stub, and resolved forwards as its own user, so the querying user is gone before any rule could look at it. Scoping DNS to the child alone needs per-session network namespaces. Out of scope.
- **Query logging.** A log of every name the child resolved is a browsing history. `plans/kids.md` rules out surveillance.
- **Writing our own resolver.** dnsmasq is packaged in Arch, is a few kilobytes, and does an allowlist in four config lines. pisafe's 3,600 lines of Go show what the alternative costs.

## What it looks like

Parent's terminal on a fresh kids install:

```
$ omarchy kids dns
tier      family
provider  Family (1.1.1.3, 1.0.0.3)
```

Network panel and menu: a fifth DNS row, Family, next to DHCP, Cloudflare, Google, and Custom. One click for anyone in `wheel`. In the child's session the row is hidden with the other privileged entries.

Turning on the strict tier:

```
$ omarchy kids dns allowlist
Installing dnsmasq...
Rendered 14 allowed domains to /etc/dnsmasq.d/omarchy-kids.conf
tier      allowlist
provider  Kids (127.0.0.1)
```

Adding a site the child asked for:

```
$ omarchy kids allow scratch.mit.edu
scratch.mit.edu allowed in browser policy and DNS
$ omarchy kids dns check scratch.mit.edu
scratch.mit.edu  allowed
$ omarchy kids dns check example.org
example.org  blocked (not on /etc/omarchy/kids/allowlist)
```

Child's session: the browser shows "site can't be reached" for a name that is not allowed. The terminal gets `0.0.0.0` for it. Clicking any DNS control brings up the polkit prompt asking for an administrator's password.

## Evaluation of omarchy-pisafe

omarchy-pisafe is a single-machine Pi-hole in Go: a DNS sinkhole daemon on `127.0.0.1:53` and `[::1]:53`, a compiled blocklist ("gravity"), three profiles, and a CLI.

What it does:

- `internal/dns/server.go` answers queries with miekg/dns. A name in the deny set (and not in the allow set) is sinkholed to `0.0.0.0` / `::`; HTTPS and SVCB records for a blocked name return NODATA so browsers do not learn alternate endpoints; CNAME targets are checked too. Everything else is forwarded and cached.
- `share/lists.json` and `internal/lists/compile.go` build the deny set from Hagezi lists (GPL-3.0) fetched from GitHub, plus packaged seeds in `share/seed/`. `packaging/pisafe-update.timer` refreshes daily. Profiles `ads`, `under18`, `under13` pick which lists apply; `share/seed/under13.txt` adds dating, Discord, and Reddit by hand.
- `internal/hostdns/hostdns.go` enables filtering by writing `/etc/systemd/resolved.conf.d/30-pisafe.conf` and `/etc/NetworkManager/conf.d/30-pisafe-dns.conf`, pinning connections with `nmcli`, and reloading the stack. The `30-` prefix sorts after `20-omarchy-dns.conf` so it wins without touching Omarchy's file.
- `internal/hostdns/uplink.go` snapshots the network's DNS servers before enabling, filtering out `127.0.0.53`, loopback port 53, and Tailscale MagicDNS. `forwardQuery` in `server.go` prefers Cloudflare and fails over to that snapshot.
- `internal/acl/acl.go` re-execs through `sudo` with a TTY and `pkexec` without one, and gates mutations on root or the `pisafe-admin` group. `packaging/pisafe.sudoers` grants that group the whole binary with a password; `packaging/org.omarchy.pisafe.policy` is `auth_admin` for polkit.
- `packaging/pisafe.service` runs as a dedicated user with a thorough hardening block. `internal/control/control.go` serves status, stats, `check`, and a recent-query log over a 0666 socket.

Reused:

- The `30-` drop-in layering above `20-omarchy-dns.conf`, both for NetworkManager and resolved. The allowlist tier uses the same ordering and the same two file locations.
- The infrastructure allow list in `share/lists.json` (`archlinux.org`, `pkgbuild.com`, `omarchy.org`, `pkgs.omarchy.org`, captive-portal probes, NTP). It seeds `default/kids/dns-allowlist`.
- The sinkhole details: NODATA for HTTPS/SVCB, CNAME checking. dnsmasq handles both for `address=` sinkholes; the acceptance test checks both.
- The privilege-free `check NAME` diagnostic, adopted as `omarchy kids dns check`.
- The README's limits paragraph: DNS is not a content filter, HTTPS paths are invisible, a VPN still bypasses.

Not reused:

- **Wrong model.** It is a blocklist. `allow.list` is an exemption list, not an allow-only mode. The under-13 posture is an allowlist. A blocklist of Hagezi data refreshed daily cannot be vouched for release by release.
- **It ships a browsing history.** `packaging/pisafe.conf` and `internal/config/config.go` default `log_queries = true`, which appends every query with a timestamp to `/var/lib/pisafe/queries.log`. `pisafe log` reads the last 256 queries from the daemon over a world-connectable socket. That is the surveillance `plans/kids.md` rules out.
- **A parallel admin group.** `pisafe-admin`, its sudoers grant, the `setfacl` work in `internal/acl/acl.go` and `packaging/pisafe.install`, and `pisafe parent add` all exist to let a non-`wheel` adult edit lists. Omarchy's parent is in `wheel`. The layer is unnecessary.
- **Fails open by default.** `upstream = auto` forwards to the DHCP resolver when Cloudflare does not answer. Right for pisafe, wrong for a family upstream.
- **A resolved bug.** `resolvedBody` in `internal/hostdns/hostdns.go` writes `DNS=127.0.0.1 ::1` without an empty `DNS=` reset first. resolved's list settings append across files, so the servers `omarchy-dns` wrote stay in the global list. NetworkManager's per-link route masks it; the drop-in is wrong on its own.
- **`disable` changes the owner's DNS.** `Disable` in `hostdns.go` pins every connection to Cloudflare and leaves them there. It never recorded what the machine used before.
- **It reimplements `omarchy-dns` in Go.** `pinConnections` and `ReloadStack` duplicate `set_connection_dns` and `reload_dns_stack`, and already differ (pisafe adds `resolvectl flush-caches`). Two copies of the reload dance will drift.
- **Delivery.** `install-omarchy.sh` is curl-pipe-bash that installs a Go toolchain and runs `makepkg` on the target. Omarchy ships packages through omarchy-pkgs, and a Go daemon adds a toolchain to the pipeline DHH signs. `packaging/pisafe-link-skill.service`, enabled globally for every user, symlinks an agent skill into `~/.claude/skills`, `~/.codex/skills`, `~/.gemini/config/skills`, and two more, including the child's home. `packaging/omarchy-menu.jsonc.example` asks the user to hand-merge menu rows.
- **Scope.** `lists known`, `lists add URL`, Firebog and StevenBlack catalogs in `share/known-lists.json`: Pi-hole feature parity, not a kids feature.
- Minor: `RequireAdmin` short-circuits on the `PISAFE_ROOT` environment variable (`paths.Dev()`); the paths move too so it is not a privilege hole, but a dev switch in the production binary is a smell. The TTL selection in `internal/dns/cache.go` `Put` is muddled.

omarchy-pisafe is a competent single-machine Pi-hole that answers a different question. It is not merged and not packaged as the kids tier. Its layering trick, infrastructure allow list, and `check` diagnostic carry over. Its daemon, lists, log, and admin group do not.

## Design

### Tiers

`/etc/omarchy/kids/dns` is root-owned, mode 0644, and holds one word.

- `off`: the machine uses whatever `omarchy-dns` provider the owner picked. Only meaningful after `omarchy kids remove` or for a parent who wants the browser policy alone.
- `family`: `omarchy-dns Family`. The default `omarchy-kids-apply` writes.
- `allowlist`: dnsmasq on loopback, allow-only, forwarding allowed names to the Family upstream. Strict mode, opt-in.

`omarchy-kids-dns [off|family|allowlist]` reads or sets the tier and applies it. `omarchy-kids-status` reports the tier and the effective provider side by side and warns when they disagree (a parent clicked a different provider in the panel).

### The `Family` provider

- `provider_from_arg` in `bin/omarchy-dns` accepts `Family`. The servers are Cloudflare for Families, malware and adult content: `1.1.1.3`, `1.0.0.3`, `2606:4700:4700::1113`, `2606:4700:4700::1003`, hostname `family.cloudflare-dns.com` for `DNSOverTLS=opportunistic`. Same shape as the Cloudflare case.
- `FallbackDNS=` is written empty for this provider. The existing providers fall back to Quad9; Family must not fall back to an unfiltered resolver.
- `current_dns_provider` tests for Family before Cloudflare, because `family.cloudflare-dns.com` contains `cloudflare-dns.com`.
- `etc/sudoers.d/omarchy-dns` gains `/usr/bin/omarchy-dns Family`. `test/shell.d/dns-sudoers-test.sh` pins the exact rule text and must change with it. Machines whose `omarchy-settings` predates the new rule fall through to `pkexec`, which `sudo_grants_passwordless` already handles.
- `default/omarchy/omarchy-menu.jsonc` gains `setup.network.dns.family` beside the four existing rows. `dnsProviders` in `shell/plugins/panels/network/Panel.qml` gains `"Family"`. Both are visual changes and go through `agents/skills/visual-verification.md`.
- Cloudflare's family resolver is a blocklist run by Cloudflare, the same trust the machine already places in `1.1.1.1`.

### The allowlist resolver

- `omarchy-kids-dns allowlist` installs `dnsmasq` with `omarchy-pkg-add` if missing. The package is not added to `install/omarchy-base.packages`; a daemon for one opt-in tier does not belong on every machine.
- `omarchy-kids-apply-web` renders `/etc/dnsmasq.d/omarchy-kids.conf`:

  ```
  # Managed by omarchy-kids-apply-web. Edit /etc/omarchy/kids/allowlist instead.
  listen-address=127.0.0.1
  bind-interfaces
  no-resolv
  bogus-priv
  address=/#/0.0.0.0
  address=/#/::
  server=/scratch.mit.edu/1.1.1.3
  server=/scratch.mit.edu/1.0.0.3
  ```

  `address=/#/` sinkholes every name; a `server=/domain/` line is more specific and wins for that domain and its subdomains. `bind-interfaces` with a loopback `listen-address` keeps dnsmasq off the LAN and away from resolved's stub on `127.0.0.53`.
- Allowed names forward to the Family upstream, so a domain a parent allowed is still filtered by Cloudflare underneath. dnsmasq speaks plain DNS upstream; the allowlist tier loses the opportunistic TLS the Family tier has.
- `/etc/systemd/resolved.conf.d/30-omarchy-kids.conf`:

  ```
  [Resolve]
  DNS=
  DNS=127.0.0.1
  FallbackDNS=
  Domains=~.
  DNSOverTLS=no
  ```

  The empty `DNS=` resets the list before the loopback entry. The drop-in survives `omarchy-dns` rewriting `/etc/systemd/resolved.conf`.
- `/etc/NetworkManager/conf.d/30-omarchy-kids-dns.conf` carries a `[global-dns-domain-*]` section with `servers=127.0.0.1`. It sorts after `20-omarchy-dns.conf` and overrides it. Connections are pinned to `127.0.0.1` with the same `nmcli connection modify` loop `omarchy-dns` uses, by calling into it rather than copying it: `omarchy-dns` gains a hidden `Kids` provider that writes nothing to `20-omarchy-dns.conf` and only pins connections and reloads. It is not in the sudoers rule and not in the menu.
- While the drop-ins exist, `omarchy-dns` with no argument reports `Kids`. `omarchy-dns <provider>` still writes its own file and prints a notice that the allowlist tier is active and the provider takes effect when the tier changes.
- Leaving the tier removes both drop-ins, disables `dnsmasq.service`, and re-runs `omarchy-dns` with the provider recorded at entry.

### One allowlist, two renderings

- `/etc/omarchy/kids/allowlist` is the single source: one domain per line, `#` comments, subdomains implied. A line is accepted only if it is lowercase labels of letters, digits, and hyphens with at least two labels. `omarchy-kids-allow` rejects anything else before it reaches a root-owned file, because the file feeds a dnsmasq config and a policy JSON.
- `omarchy-kids-apply-web` (hidden, root) renders from that file plus `default/kids/dns-allowlist`, the shipped infrastructure list: Omarchy and Arch package hosts, the hostnames in `/etc/pacman.d/mirrorlist` read at render time, GitHub for plugins and themes, the captive-portal probe names, NTP. Without it the allowlist tier breaks `omarchy update` for the parent.
- Browser side, Chromium family: `omarchy-kids.json` in each directory `BROWSER_POLICY_MANAGED_DIRS` names, with `URLBlocklist: ["*"]` and `URLAllowlist` entries of the form `[*.]scratch.mit.edu`. Firefox and Zen have a single `policies.json` per distribution directory and no drop-in mechanism, so the kids version is `default/firefox/policies.json` merged with `default/kids/firefox-policies.json` and the `WebsiteFilter` exceptions, then installed through `browser_policy_install_firefox_policies` with the rendered path. `browser_policy_setup_firefox_distribution` re-renders when `/etc/omarchy/kids/allowlist` exists, so `omarchy-install-browser firefox` on a kids machine does not reinstall the stock file.
- The DNS side needs more names than the browser side. Chromium's URL allowlist checks navigations, not subresources, so an allowed site loads its CDN assets. A DNS allowlist blocks the CDN too. The shipped list covers infrastructure; a parent who hits a broken site adds the CDN with `omarchy kids allow`, and `omarchy kids dns check` tells them which name is blocked. So `family` is the default and `allowlist` is strict mode.
- DNS keys in the kids browser policy, beside the safe search, incognito, and extension keys from `plans/kids.md`: Chromium `DnsOverHttpsMode: "off"`, `BuiltInDnsClientEnabled: false`, `ProxySettings: {"ProxyMode": "direct"}`; Firefox `DNSOverHTTPS: {"Enabled": false, "Locked": true}`, `Proxy: {"Mode": "none", "Locked": true}`. DoH off forces the browser through the system resolver. Proxy locked to direct stops the browser being pointed at a SOCKS proxy that resolves names remotely. Extension installs blocked stops VPN extensions.
- `browser_policy_purge_dir` deletes entries in a managed directory not owned by root. The kids JSON is root-owned and survives; `omarchy-theme-set-browser-policy` keeps writing `color.json` beside it.

### Why the child cannot undo it, and where that stops

Holds:

- Every file the tiers write is root-owned: the two drop-ins under `/etc/NetworkManager/conf.d` and `/etc/systemd/resolved.conf.d`, `/etc/systemd/resolved.conf`, `/etc/dnsmasq.d/omarchy-kids.conf`, `/etc/omarchy/kids/*`, the managed policy directories, `/etc/hosts`, and the `/etc/resolv.conf` symlink to resolved's stub. The child can read them and cannot write them.
- `omarchy-dns` and `omarchy-kids-*` are privileged. The sudoers grant is `%wheel`; the child is not in it, so `sudo_grants_passwordless` is false, and the command lands on `pkexec`. That prompt asks for an administrator's password.
- Changing resolved's per-link servers with `resolvectl dns` or `resolvectl revert` is the polkit action `org.freedesktop.resolve1.set-dns-servers`, `auth_admin` for active sessions. Same prompt.
- NetworkManager's polkit policy may let an active local user edit connections; Arch builds it that way. A `[global-dns-domain-*]` section overrides per-connection DNS entirely, which is why `omarchy-dns` writes the global section and not only the per-connection pins. A connection the child creates or imports, including a WireGuard tunnel NetworkManager supports natively, still resolves through the configured filter. The acceptance test covers this.
- `/etc/hosts` is root-owned. A child cannot map a name around the filter with it.

Does not hold:

- A program that carries its own resolver and skips resolved. `dig @8.8.8.8`, `curl --doh-url`, a Python script, a Go binary. The child keeps the terminal (`plans/kids.md`). With DoH off and proxy locked in the browser, an IP address obtained this way is little use against HTTPS sites that need a hostname.
- A userland proxy or Tor binary downloaded into `$HOME`. SOCKS with remote resolution and Tor both resolve names elsewhere, and neither needs root. Only an egress firewall rule keyed on the child's uid narrows this, and DoH over 443 to an arbitrary IP cannot be told from HTTPS. Not stopped. An outbound rule for the child's uid that rejects port 53 off loopback and port 853 anywhere, inserted into `/etc/ufw/before.rules` the way ufw-docker inserts its block, is an open question for the allowlist tier.
- A VPN that needs root, a package install, or a new kernel interface. Those already end at the polkit prompt.
- HTTPS paths and content on an allowed domain. DNS sees hostnames. This is a guardrail against accidental exposure for children under 13, not a jail.

### Parent commands

All in the `kids` group. Privileged commands use the `omarchy-dns` pattern: `sudo` when a terminal is attached, `pkexec` otherwise, PATH pinned when root, and carry `# omarchy:requires-sudo=true`.

- `omarchy-kids-dns [off|family|allowlist]`: show or set the tier. Setting records the current `omarchy-dns` provider in `/var/lib/omarchy/kids/dns-before` on the first change so `off` and `omarchy-kids-remove` can restore it.
- `omarchy-kids-dns check <domain>`: unprivileged. Under `allowlist`, reports allowed or blocked by matching the rendered config, and names the file the domain would need to be in. Under `family`, queries the resolver and reports whether the answer is the sinkhole `0.0.0.0`.
- `omarchy-kids-allow <domain>` and `omarchy-kids-deny <domain>`: validate, edit `/etc/omarchy/kids/allowlist`, run `omarchy-kids-apply-web`.
- `omarchy-kids-apply-web`: hidden, root, idempotent. Renders the browser policy files and, when the tier is `allowlist`, the dnsmasq config, then reloads dnsmasq. Called by `omarchy-kids-apply`, `omarchy-kids-allow`, `omarchy-kids-deny`, `omarchy-kids-dns`, and the Firefox distribution helper.
- No NOPASSWD rules for any of these. The parent types a password in their terminal; only the panel's one-click `Family` toggle goes through the extended `omarchy-dns` grant.
- The `setup.network.dns.*` menu rows and the panel's DNS row are hidden when `omarchy-kids-active` succeeds, with the other privileged entries (`plans/kids.md`).

### Existing installs

- `omarchy-kids-apply <child>` writes `/etc/omarchy/kids/dns` with `family` if absent, records the pre-kids provider, and calls `omarchy-kids-dns` to apply the tier. Running as root, `omarchy-dns` skips its own elevation, so nothing prompts in the middle of a setup wizard.
- Re-running `omarchy-kids-apply` re-renders the same files. A tier already applied is a no-op apart from the rewrite.
- `omarchy-kids-remove <child>` sets the tier to `off`: drop-ins removed, dnsmasq disabled, the recorded provider restored through `omarchy-dns`, the kids policy JSON removed from the managed directories, and the stock Firefox `policies.json` reinstalled. The `Family` provider itself stays available as an ordinary `omarchy-dns` choice.
- No migration. Machines that were never kids machines have nothing to migrate; the new sudoers rule and menu row arrive with the package.

### Tests

- `test/shell.d/dns-sudoers-test.sh`: rule text gains `Family`; the elevation loop covers it; `Kids` must not appear in the rule.
- New `test/shell.d/dns-family-test.sh`: `provider_from_arg` accepts `Family`; `current_dns_provider` reports `Family` for a `20-omarchy-dns.conf` naming `1.1.1.3`, `Kids` when the `30-` drop-in exists, and `Cloudflare` unchanged for the stock file. The read-only path runs inside `unshare --user --map-root-user --mount` with a fake `/etc/NetworkManager/conf.d` bind-mounted over the real one, and skips where user namespaces are refused, as the sudoers test already does. The resolved.conf written for `Family` has an empty `FallbackDNS=`.
- New `test/shell.d/kids-dns-test.sh`: `omarchy-kids-apply-web` takes input and output paths so it renders unprivileged into a temp directory, the way `test/shell.d/browser-policy-dir-test.sh` drives the policy helpers. Assertions: exact dnsmasq output for a fixture allowlist; mirrorlist hostnames present; invalid lines (`bad domain`, `evil.com/#`, a bare TLD, uppercase, a trailing dot) rejected or normalized; the Chromium JSON parses with `jq` and carries `DnsOverHttpsMode: "off"`; the merged Firefox JSON still carries the stock `Preferences`.
- `test/cli`: the metadata lint picks up the new `kids` commands; `omarchy kids dns --help` never executes.
- `test/acceptance.d/kids-dns-test.sh`, in the VM: as the child, `getent hosts` of a blocked name returns the sinkhole under `allowlist` and a real answer for an allowed name; `omarchy update` succeeds under `allowlist`; `omarchy-dns Cloudflare` from the child's session without a terminal produces a polkit prompt, not a change; `resolvectl dns <link> 8.8.8.8` as the child is denied; a connection the child adds with `nmcli` does not change the effective resolver; the HTTPS record for a sinkholed name is empty.
- Visual: the Family row in the network panel and the menu, light and dark, and the hidden row in a kids session.

## Relationship to plans/kids.md

- No conflicts. The parent is in `wheel`, the child is not; every rule is a root-owned file; the first tier is a family upstream through `omarchy-dns`; the local resolver is a later tier.
- The later tier is dnsmasq, allow-only, on loopback. Replace "a local allowlist resolver" in `plans/kids.md` with that.
- `omarchy-kids-dns` joins the command list; the "What it looks like" section of `plans/kids.md` already shows the parent changing the DNS tier through `omarchy kids`. `omarchy-kids-apply-web` joins as a hidden helper so allow and deny do not re-run the whole apply script. Add both to the command list in `plans/kids.md`.
- `Family` fails closed with an empty `FallbackDNS=`. Add to `plans/kids.md`.
- DNS is machine-wide and applies to the parent. Per-user DNS needs network namespaces. Extend the browser-policy scope open question in `plans/kids.md` to DNS.
- `/etc/omarchy/kids/allowlist` has a strict line format: lowercase labels of letters, digits, and hyphens, at least two labels. Add the format to `plans/kids.md`.

## Rollout

1. `Family` provider: `omarchy-dns`, the sudoers rule, the menu row, the panel row, `dns-sudoers-test.sh`, `dns-family-test.sh`. Usable on any machine, kids or not. The DNS half of `plans/kids.md` step 3.
2. Kids browser policy DNS keys and `omarchy-kids-apply-web` rendering the browser side from `/etc/omarchy/kids/allowlist`, with the Firefox merge. Lands with the browser policy work, after `plans/kids.md` step 2.
3. `omarchy-kids-dns` with `off` and `family`, wired into `omarchy-kids-apply` and `omarchy-kids-remove`, plus `omarchy-kids-status` drift reporting.
4. The `allowlist` tier: dnsmasq render, the two `30-` drop-ins, the hidden `Kids` provider in `omarchy-dns`, `check`, `default/kids/dns-allowlist`, `kids-dns-test.sh`, the acceptance test.
5. Manual page for parents: what each tier does, what it does not do, and the CDN caveat for strict mode. `docs/` reference for the drop-in layering so the next person who touches `omarchy-dns` knows the `30-` files exist.

Steps 1 and 2 are independent. Step 4 waits on step 3.

## Open questions

- **Egress rule for the child's uid.** Rejecting port 53 off loopback and port 853 for the child's uid closes the copy-pasteable `dig @8.8.8.8`. It means editing `/etc/ufw/before.rules` and trusting iptables-nft owner matching under ufw. Spike it, then decide whether it joins step 4 or stays out.
- **A blocked-name diagnostic without a log.** `check` answers "is this name blocked". It does not answer "what did the browser just fail to load", which is what a parent debugging a broken site wants. A short in-memory ring of the last few sinkholed names, never written to disk and cleared on reload, is a possible middle. Decide before step 4.
- **Drift re-assertion.** A parent who clicks Google in the panel leaves the tier file saying `family` and the machine unfiltered until someone reads `omarchy-kids-status`. Options: a root timer that re-applies the tier, or `omarchy-dns` refusing non-Family providers while the tier file says `family` unless given `--force`. Preferred: the refusal; one prompt, no daemon.
- **Family provider choice.** Cloudflare for Families is the default because the machine already trusts Cloudflare. CleanBrowsing and OpenDNS FamilyShield are alternatives with different lists. One provider in the first version; a second only if parents ask.
- **Captive portals.** With Family DNS failing closed, a portal that intercepts DNS still works because it answers everything itself, but a network that blocks `1.1.1.3` outright leaves the machine without DNS until a parent picks DHCP. Acceptable for the first version; note it in the manual.
- **Multiple children.** The allowlist and tier are per machine. Per-child lists need per-user DNS, which is out of scope.
