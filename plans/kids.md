# Plan: Kids — a child-safe Omarchy inside the main project

Revision 1.

## Problem

Omarchy Kids is a variation of Omarchy for children under 13. It must stay part of the main project: not a fork, not a separate desktop, not a separate distribution. DHH signs every release, so every kids feature has to be something he can vouch for.

The constraints set so far:

- Kids mode is chosen during install. The first question becomes "Who is this computer for?" with the answers Me, Child, and Another owner. Today the only way to install for someone else is Ctrl+C on the keyboard step.
- A child cannot change settings. Changing settings requires sudo, and the child does not have it.
- Younger than 13 first. Teenagers are a later problem.
- Work already underway in the community, in the order the channel lists it: onboarding and parent/child setup, an onboarding mascot, a DNS allowlist, a screen time tracker, a sandbox mode for existing installs, and parent approval.

Nothing in the repo knows about a child today. Every account the installer or first boot creates lands in `wheel` (`user_groups` in `bin/omarchy-provision-owner`), the menu shows Install, Update, and System to everyone, and browser policy and DNS are configured once for the machine with no per-user distinction.

## Shape

One rule: the parent is in `wheel`, the child is not. Everything else follows from it.

- Kids mode creates two accounts at install. The parent account is the machine owner and unlocks the disk. The child account has no sudo.
- Every rule the child must not undo lives in root-owned configuration. Nothing under the child's home is trusted for enforcement.
- The child's desktop is ordinary Omarchy with a kids theme, a curated menu, and a preinstalled plugin set. Fun and educational content ships as themes and plugins tagged `kids` and `education`, not as core code.
- Privileged actions from the child's session already fall through to polkit, which prompts for an administrator's password. That prompt is parent approval at the keyboard. The parent's phone is the first-class approval path and is designed in `plans/kids-approval.md`.
- One shared script applies the kids configuration. The install path and the sandbox mode for existing installs both call it, so they cannot drift.

## Rejected approaches

- **A separate desktop, session, or ISO.** Doubles the surface DHH has to vouch for and forks the update pipeline. Kids mode is a set of accounts and root-owned files on a stock install.
- **Enforcement in the child's `~/.config`.** A child who can open a terminal can edit it. Every rule is root-owned or a group membership.
- **A local filtering resolver in the first version.** A family-filtering upstream provider through the existing `omarchy-dns` path gives most of the benefit with no daemon to maintain. The later tier is dnsmasq, allow-only, on loopback.
- **Surveillance features.** No keylogging, screenshots, or browsing history reports to the parent. The DNS allowlist controls access without surveillance.
- **A custom approval daemon.** Approval is a root-owned request queue plus decisions the parent authenticates, not a long-lived root process with a socket the child can write to.
- **Hiding the terminal.** Omarchy is a learning machine. The child keeps the terminal; the terminal simply has no sudo.

## What it looks like

Install. The configurator asks "Who is this computer for?" Choosing Child asks for the parent account first, then the child's display name and a simple password or PIN. The machine reboots into the child's desktop.

Child's desktop. A kids theme is active. The menu has Learn, Play, Create, and Settings with only user-level items. Install, Update, System, and Remove are absent. The browser opens with an allowlist and safe search enforced, and cannot open a private window. After the daily screen time budget, the session locks with a friendly message and the parent's password unlocks it.

Parent's desktop. Stock Omarchy. `omarchy kids` shows the child's status and lets the parent change the allowlist, screen time budget, DNS tier, and installed plugins. Every change is a privileged command run in the parent's terminal or through pkexec. Requests from the child arrive on the parent's phone and are approved with one tap.

Existing installs. `omarchy setup kids` on a stock machine creates the child account and applies the same configuration the installer would have. `omarchy kids remove` reverses it, keeping the child's home.

## Design

### Account model

- The parent account is created exactly as the owner is today, in `wheel`, with the LUKS key.
- The child account is created with `useradd -m` and no `wheel`. It joins a new `omarchy-kids` system group. Group membership is the single source of truth for "this is a child session"; no config flag duplicates it.
- Autologin targets the child so the machine boots straight into their desktop. The parent logs in from SDDM or by switching user.
- `omarchy-kids-active` exits 0 when the current user is in `omarchy-kids`. It is the predicate every guard and hook uses.

### Install question

- The "Who is this computer for?" prompt is added to `install/provisioning/setup-form.sh`, so the ISO configurator and first-boot provisioning ask the same question. The ISO side of this change lives in the omarchy-iso repository.
- Choosing Child writes `/var/lib/omarchy/provisioning/child` holding the child's username and display name, next to the existing `setup-user` and `groups` files.
- `omarchy-provision-owner` reads the marker after creating the parent, creates the child, and calls `omarchy-kids-apply`. The marker is removed in `cleanup_oem_state` with the other provisioning files.
- Choosing Another owner replaces the current Ctrl+C side channel on the keyboard step with an explicit answer. The deferred provisioning it triggers is unchanged.

### Shared apply script

- `omarchy-kids-apply <child>` is the one place that turns a stock machine into a kids machine. It is idempotent, runs as root, and is called by first boot and by `omarchy-setup-kids`.
- It creates the `omarchy-kids` group, adds the child, writes the root-owned files under `/etc/omarchy/kids/`, sets the kids theme for the child, installs the default kids plugin set into the child's home, and configures autologin.
- `omarchy-kids-remove <child>` reverses each step in the opposite order and leaves the home directory in place.
- State the parent can change lives in `/etc/omarchy/kids/`: `allowlist`, `screen-time.conf`, and `dns`. All files are root-owned, mode 0644, so the child can read but not change them. `allowlist` holds one domain per line: lowercase labels of letters, digits, and hyphens, at least two labels.

### Web access

- DNS: `omarchy-dns` gains a `Family` provider that points NetworkManager at a family-filtering resolver and fails closed, with no fallback to the DHCP resolver. The sudoers rule in `etc/sudoers.d/omarchy-dns` is extended to include it, so the parent can toggle it from the network panel. The child cannot run it: the rule is for `%wheel`. DNS is machine-wide and applies to the parent's session too. Tiers, the later dnsmasq allow-only resolver on loopback, and the limits of DNS filtering are in `plans/kids-dns.md`.
- Browser: `omarchy-kids-apply` writes a kids policy into the managed policy directories that `install/helpers/browser-policy.sh` already hardens (`/etc/chromium/policies/managed` and the Chrome, Edge, Brave, and Firefox equivalents). The policy sets an allowlist, forces safe search, disables incognito and private windows, and disables extension installs. The allowlist is generated from `/etc/omarchy/kids/allowlist`.
- Machine policy applies to every profile on the machine, including the parent's. Scoping it to the child is an open question.
- `omarchy kids allow <domain>` and `omarchy kids deny <domain>` edit the allowlist and regenerate the policy. Both are privileged.

### Menu

- Entries the child must not see gain a `when` guard of `! omarchy-kids-active`. This covers Install, Remove, Update, System, and every entry that runs a privileged command. Guards are batched and evaluated by the shell; once `omarchy-kids-active` is used by more than one row it is added to `GUARD_READERS` in `MenuModel.js`, as `docs/menu.md` requires.
- A `kids` submenu with Learn, Play, and Create groups is visible only when `omarchy-kids-active` succeeds. Its entries come from installed plugins, so the core menu does not hardcode apps.
- No aliases on the new entries.

### Screen time

- `omarchy-kids-screentime` is a root-owned system service and timer. It reads `/etc/omarchy/kids/screen-time.conf` for a daily budget and allowed hours, counts active session time for `omarchy-kids` users with logind, and records the day's total under `/var/lib/omarchy/kids/`.
- At the budget it locks the child's session through the existing lock path and posts a notification a few minutes ahead. Allowed hours are enforced with `pam_time` in `/etc/security/time.conf`, so a login outside the window never starts.
- The parent's password unlocks the session and grants a one-off extension of a configurable length. The extension is recorded so the budget is not silently reset.
- The bar shows remaining time in the child's session through a small widget shipped with the shell, guarded by `omarchy-kids-active`.

### Parent approval

- The child's session cannot run `sudo`. Privileged commands invoked without a terminal already `exec pkexec`, which prompts for an administrator's credentials. That prompt is the approval flow: the parent types their password on the child's screen.
- Prerequisite: the shell's polkit agent in `shell/plugins/polkit/PolkitAgent.qml` shows only a password field and never selects an identity. From a non-wheel session it has no way to authenticate as the parent. Step 2 of the rollout adds an identity chooser that lists `wheel` members when the caller is not one, so the prompt can ask for the parent's password.
- Plugin installs go through `omarchy-plugin-add`, which is unprivileged. In a kids session the plugin set is pinned: `omarchy-plugin-add` refuses when `omarchy-kids-active` succeeds unless a parent-held token exists for that plugin. The token is a root-owned file under `/var/lib/omarchy/kids/unlock/<child>/` keyed by the plugin URL, created with `omarchy kids unlock <url>`. A per-plugin token approves one thing the parent saw; a time window would approve everything installed inside it.
- The richer flow (a request queue, the parent notified in their own session or on their own device) is designed in `plans/kids-approval.md` and is out of scope for the first release.

### Theme, mascot, and plugins

- A `kids` theme ships in `themes/` with bright colors and larger defaults for font and cursor size, using the existing `colors.toml` and templates. The mascot appears in the onboarding welcome and the lock screen message. The neutral path is the default; boy and girl variants are a selectable theme option, not separate code paths.
- The first-run welcome for a child replaces the keybinding notification in `install/user/first-run/welcome.sh` with a mascot-led tour, gated by `omarchy-kids-active`.
- The default kids plugin set is a short list in `install/omarchy-kids.plugins`, installed by `omarchy-kids-apply`. Plugins must carry the `kids` or `education` tag to be included.

### Command group

- New group `kids` with the entry `GROUP_DESCRIPTIONS[kids]="Child account and parental controls"` in `bin/omarchy`.
- Commands: `omarchy-kids-active`, `omarchy-kids-apply`, `omarchy-kids-remove`, `omarchy-kids-status`, `omarchy-kids-allow`, `omarchy-kids-deny`, `omarchy-kids-dns`, `omarchy-kids-unlock`, `omarchy-kids-screentime`, and the hidden `omarchy-kids-apply-web`, which re-renders the browser policy and resolver config so allow and deny do not re-run the whole apply script. Setup for existing installs is `omarchy-setup-kids` under the existing `setup` group. The approval flow adds `omarchy-kids-ask`, `omarchy-kids-approve`, and `omarchy-kids-reject`; `deny` stays the allowlist verb.
- Privileged commands follow the sudo/pkexec rule in `default/agents/skills/omarchy/SKILL.md` and carry `# omarchy:requires-sudo=true`.

### Related plans

- `plans/kids-dns.md`: filtering tiers, the `Family` provider, the later allowlist resolver, and an evaluation of the omarchy-pisafe experiment.
- `plans/kids-approval.md`: the request queue, parent notification, signed decisions, and an evaluation of the [omarchy-parentapproval](https://github.com/aphexddb/omarchy-parentapproval) experiment.

## Rollout

1. Account model and predicate: the `omarchy-kids` group, `omarchy-kids-active`, and the "Who is this computer for?" question in the shared form and first boot. Tests for the form statuses and the provisioning marker.
2. `omarchy-kids-apply` and `omarchy-kids-remove`, plus `omarchy-setup-kids` for existing installs, and the identity chooser in the polkit agent. This is the sandbox mode work; it ships before any content so every later piece has one place to hook in.
3. Web access: the `Family` DNS provider and the kids browser policy.
4. Menu guards and the `kids` submenu.
5. Kids theme, mascot, welcome tour, and the default plugin set.
6. Screen time service, `pam_time` windows, and the bar widget.
7. Unlock token and plugin pinning, the request queue, and phone approval, offered during `omarchy-setup-kids`. The keyboard prompt alone requires the parent at the child's screen, so the phone path ships with the queue rather than after it.

Each step is usable on its own and lands as its own PR. Steps 3 through 7 can proceed in parallel once step 2 is merged.

## Open questions

- **Browser policy scope.** Managed policy applies machine-wide. Scoping the allowlist to the child alone may require the parent to use a browser the policy does not cover, or a session-level wrapper that points the child's browser at a second policy directory. DNS has the same scope: it is machine-wide, and per-user DNS needs network namespaces. Needs a spike before step 3.
- **Child password.** No password makes the lock screen meaningless; a password a six-year-old can type is weak by design. Proposed: a short PIN, with the parent's password always accepted at the lock screen.
- **Updates.** The child's session cannot run `omarchy-update`. Updates run from the parent's session, or a root-owned timer applies them. Decide whether unattended updates are acceptable on a kids machine.
- **Screen time across reboots.** The daily total is written to disk on every tick, but a clock change can defeat it. Acceptable for the first version.
- **Multiple children.** The account model supports several `omarchy-kids` users, but screen time and allowlists are per-machine. Approval requests carry the child and the phone groups them by child. Per-child screen time and allowlists are a follow-up.
- **Teenagers.** A 13-plus mode with a looser allowlist and no screen time lock is a different set of defaults on the same model, deferred until the under-13 path ships.
