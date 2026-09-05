# Plan: Kids mode, phase 0 — the child profile and its two passwords

Revision 2. Rev 2 incorporates direction from DHH (2026-09-01): kids mode is an install profile chosen at a new first question, the installer asks for a kid password and a parent password that both unlock LUKS, the parent password becomes sudo, a `sudo omarchy-parent` bin controls things afterwards, and the work is built against `omacom/omarchy` and `omacom/omarchy-iso`. It also records the least-privilege decision from review: the kid account is not in `wheel`.

## Direction

From the project owner, verbatim in substance:

1. Kids mode is triggered during the initial install. The Ctrl+C-on-the-keyboard-screen path into "set up for another owner" becomes a real first question: **Who is this computer for? 1) Me 2) Child 3) Another owner**.
2. Child selects a different install profile, which is what will carry the different apps and themes.
3. The installer asks for both a kid password and a parent password. The parent password becomes sudo. The kid password is the normal login. Both unlock LUKS.
4. Once in, a `sudo omarchy-parent` bin controls things.
5. Later, under it: DNS whitelist, themes, and so on.
6. Build everything against `omacom/omarchy` and `omacom/omarchy-iso`.

## Problem

Omarchy has exactly one secret per install. The shared setup form's password prompt says so in its placeholder ("Used for user + root, and disk encryption when enabled"); the ISO's `configurator` writes that one hash to both the account and `root_enc_password` in `user_credentials.json`, hands the same string to archinstall as the LUKS passphrase, and creates the user with `sudo: true`, which puts it in `wheel`. `bin/omarchy-provision-owner` does the same for deferred installs at first boot. Polkit's stock admin rule is `unix-group:wheel`. So whoever can log in or unlock the screen can also install packages, change system settings, factory-reset the machine, or hand themselves passwordless sudo.

For a child's machine that is the wrong shape. The kid must boot it, log in, unlock it, connect to Wi-Fi, and switch themes without help. Everything that reaches root must stop for a parent.

## Phase 0 scope

In:

- The "Who is this computer for?" question, and the **child profile** it selects: a marker on the installed system, a predicate command, and an `--profile` flag on `omarchy-apply-system`, so both repos and every later phase key on one fact.
- The **kid password** and **parent password**, asked on child installs by the ISO and, after a factory reset of a child machine, by first-boot provisioning. Both unlock LUKS.
- The privilege posture on child installs: parent password is root's password; `sudo` asks for it; polkit prompts for it; the kid account is outside `wheel` with an explicit per-account grant.
- `bin/omarchy-parent` with its first subcommand, `password`, plus the hidden `apply` plumbing the installers call.
- The polkit dialog saying "Parent password", the timezone menu learning to prompt, fingerprint and FIDO2 copy, the manual, docs, and tests in both repos.
- The package-list hook for the child profile (an empty `install/omarchy-child.packages` the ISO already vendors and prunes its mirror for), so phase 1 only has to fill it.

Out, for later phases: the child app and theme set itself, `omarchy-parent dns` (the DNS whitelist), screen time, a parent unlocking the kid's lock screen, converting an existing "Me" install into a child install, and a separate parent login account.

## The model

Two passwords, one account, on child installs only. "Me" installs keep today's single password exactly as they are.

- **Kid password** = the account password. SDDM login, the Quickshell lock screen, and the LUKS passphrase the kid types at boot. The parent password opens the lock screen as well (Peter's call on 2026-09-01 after the ThinkPad trial): `omarchy-apply-lock` writes a child install's password stack to try the kid's password first and then hand the typed password to `bin/omarchy-parent-unlock`, which asks `sudo -k -S true` whether it is root's under `rootpw`; `-k` keeps the credential cache out of it, so a parent's unlock leaves no passwordless sudo behind, and root's faillock limit applies to guesses. The kid's password is tried first so a normal unlock never touches sudo. The same block goes into `/etc/pam.d/sddm` on child installs (Peter's reviewers' point on 2026-09-02: after a logout, or on an unencrypted install past its first boot, the login screen is the only way in, and autologin does not cover it), built from a kept copy of the packaged file with only the `auth include system-login` line expanded, and restored outside the profile. SDDM's greeter runs PAM as root, so the helper drops to the account PAM names before asking `sudo`; run as root, `sudo` would ask nothing and any password would pass. The fingerprint stack is unchanged. Known limit, documented: ten wrong tries on the kid's account lock it for two minutes, parent password included, since `pam_faillock` leads both stacks.
- **Parent password** = root's password. `sudo` asks for it through `Defaults rootpw`; polkit prompts for it through an admin rule naming `unix-user:root`; `su` and a tty root login already use it. It also unlocks LUKS, as a second key slot, so a parent can always boot the machine and reset a forgotten kid password with `sudo passwd <kid>`.
- **The kid account is not in `wheel`.** Its sudo access is an explicit per-account grant (`<kid> ALL=(ALL:ALL) ALL`) that `rootpw` turns into "anyone at this keyboard who knows the parent password". Nothing keyed on `wheel`, today or from a package installed later, reaches the kid. Of the three shipped passwordless `%wheel` grants, only the browser-accent write (`etc/sudoers.d/omarchy-theme-browser`) is re-granted to the kid: it writes a six-hex-digit color and nothing else, and a parent prompt on every theme switch would be pointless friction. The DNS toggle and the timezone menu stay `%wheel`, so from the kid's session they ask for the parent password; switching resolvers and shifting the clock are exactly the knobs the DNS whitelist and a screen-time phase must keep away from the kid.
- **Wi-Fi asks the parent by default.** Peter's call on 2026-09-01: joining a network keeps asking for the parent password, and `sudo omarchy-parent wifi kid` hands it to the kid for the school's network; the setting lives in `/etc/omarchy/parent.conf`, the file that later parent settings join.
- **No passwordless root on the menu.** _Setup > Security > Passwordless Sudo_ and _Sudoless Docker_ grant the invoking account, which on a child install is the kid's once a parent has typed the password; both are hidden there (2026-09-02).
- **Profile-gated.** The drop-ins, the grant, and `omarchy-parent` all key on the child profile. On a "Me" install root equals the account password and nothing changes, and `omarchy-parent` refuses to run.

Why root's password rather than a new identity: sudo can only ask for the invoking user's password, root's (`rootpw`), or the run-as user's (`targetpw`/`runaspw`); there is no "ask for user X". Root is the one identity every privileged entry point already authenticates, so the split needs no PAM surgery and no daemon.

Verified against the mechanisms involved:

- sudoers(5): `rootpw` — "sudo will prompt for the root password instead of the password of the invoking user". `NOPASSWD` entries skip authentication entirely. `passprompt` accepts `%p`, "the user whose password is being asked for (respects the rootpw ... flags)". `/etc/sudoers.d` files are parsed in lexical order and names containing a `.` are skipped.
- polkit(8): rules directories are processed in lexical order of basename, `/etc/polkit-1/rules.d` winning ties, and admin-rule functions run in order "until one of the functions returns a value". A `40-omarchy-parent.rules` returning `["unix-user:root"]` precedes the package's `50-default.rules` (`unix-group:wheel`). polkit's JS authority also falls back to root when no admin identity is returned at all.
- Quickshell's polkit service (`src/services/polkit/flow.hpp`): `AuthFlow.identities` is the list polkit offered, `selectedIdentity` defaults to the first one, and the PAM session runs for that identity. Under the rule polkit offers exactly one identity, root, so `shell/plugins/polkit/PolkitAgent.qml` needs no identity picker.
- archinstall (`orchestrator/archinstall_adapter.py`): `create_users` honors each user's `sudo` flag, and `root_user` takes `root_enc_password` from the credentials, so the ISO can hand it the parent hash for root and `sudo: false` for the kid with no adapter change.

## Rejected approaches

- **Applying the two-password posture to every install.** DHH's direction makes kids mode a profile; "Me" installs keep one password. Everything below is gated on the child profile.
- **Leaving the kid in `wheel`.** Convenient for phase 0, since the shipped grants keep working and provisioning, the ISO, and several tests assume it. Rejected: `wheel` is the conventional administrator signal and every rule that keys on it would silently extend to the kid. The one harmless convenience is re-granted explicitly instead.
- **A separate parent login account.** sudo from the kid's session would still need `rootpw` and root's password, so a second account buys nothing for the password split, and it adds a second home directory, a second user on the SDDM screen, and a parent who logs the kid out to administer the machine. The sibling `omarchy-kids` project assumes this topology; the root-identity rule composes with it (a later phase can return `["unix-user:root", "unix-group:wheel"]`), so it remains a later-phase option.
- **A custom PAM stack that knows about "the parent".** Reinvents identity selection that sudo and polkit already do; every entry point would need patching.
- **`Defaults targetpw` or `runaspw`.** Same effect for `sudo cmd`, but `targetpw` changes what `sudo -u other` asks for; `rootpw` says exactly what is meant.
- **Shipping the drop-ins as static files under `etc/`.** Static files reach every install at the next `omarchy-settings` upgrade, including "Me" installs and machines whose owner changed their login password with `passwd` (root no longer equals the account, so `rootpw` would demand a password they may not remember). The drop-ins are written by `omarchy-parent apply`, called from the install leaf on child installs and from first-boot provisioning.

## Threat model, stated plainly

- Defends against: the kid, or anything running as the kid, installing or removing software, running `omarchy update`, changing system configuration through `sudo` or `pkexec`, enabling sudoless Docker or passwordless sudo, factory-resetting the machine, changing DNS or the clock, and, in later phases, disabling parental controls that live behind root. Also anything a shipped or third-party rule grants to `wheel` members, since the kid is not one.
- Does not defend against physical attacks. The kid knows a LUKS passphrase, and Omarchy asks users to disable Secure Boot, so a live USB plus `chroot` plus `passwd root` defeats the split. A BIOS password and a locked boot order are the parent's job; the manual says so.
- Does not filter the web. Phase 0 gates root, and browsing never touches root. NetworkManager's default policy lets any active session edit connection DNS without a prompt, Chromium's own secure-DNS setting bypasses the system resolver, and a browser run from the home directory ignores system policy. The DNS whitelist phase owns those; phase 0's contribution is that "an administrator must authenticate" now means the parent instead of the kid.
- Not changed: sudo's credential cache. After a parent types the password in a terminal, that terminal keeps passwordless sudo for `timestamp_timeout` (sudo's default is five minutes), and polkit's `auth_admin_keep` actions keep their authorization for a similar window. `omarchy-sudo-keepalive`, used by `omarchy update` and `omarchy-pkg-install`, depends on that cache, so it stays; the manual tells parents to close the terminal when done.

## Naming

| Thing | Name |
| --- | --- |
| The profile | `child` (the other value is `default`) |
| Profile marker on the installed system | `/etc/omarchy/profile`, one word |
| Profile predicate | `bin/omarchy-profile-child` (exit 0 on a child install), group `profile` |
| The passwords | "kid password", "parent password" |
| Control command | `bin/omarchy-parent`, run as `sudo omarchy-parent <subcommand>` |
| System drop-ins | `/etc/sudoers.d/omarchy-parent`, `/etc/polkit-1/rules.d/40-omarchy-parent.rules` |
| Per-account grant | `/etc/sudoers.d/omarchy-parent-<kid>` |
| Lock screen helper | `bin/omarchy-parent-unlock`, run by `pam_exec` from `/etc/pam.d/omarchy-lock-password` on child installs |
| The parent's settings | `/etc/omarchy/parent.conf`, `key=value` lines, world-readable; `wifi=parent\|kid` so far |
| Wi-Fi rule | `/etc/polkit-1/rules.d/45-omarchy-parent-wifi.rules`, written from `parent.conf` for the kid account |
| Shared helper for feature commands | `install/helpers/parent.sh` (`install_sudoers`, and `conf_get`/`conf_set`/`conf_document` for `parent.conf`) |
| Feature commands | `bin/omarchy-parent-<feature>`, reached as `omarchy-parent <feature> ...` |
| sudo prompt | `[sudo] parent password: ` |
| Package list hook | `install/omarchy-child.packages` |

## Design: omarchy

### 1. Shared setup form (`install/provisioning/setup-form.sh`)

The form is vendored onto the ISO by `build-iso.sh` and sourced by both `configs/airootfs/root/configurator` and `bin/omarchy-provision-owner`, so every new question lives here once.

- `omarchy_prompt_computer_for`: a `gum choose` over "Me", "Child", "Another owner", writing `computer_for` as `me`, `child`, or `other`. Same 0/1/130 status contract; Esc on the first screen re-asks, as the keyboard prompt does today. Arrow keys work under any layout, so it can precede the keyboard step as DHH asks.
- `omarchy_prompt_parent_password`, writing `parent_password` and `parent_password_confirmation`, using the same `x=$(gum ...) && status=0 || status=$?` capture (one caller runs under `set -e`). Notices: "Parent password can't be blank!", "Parent passwords didn't match!", and "Parent password must differ from the kid password" when `$password` is non-empty and equal. Placeholder: "For sudo, updates, and installs — keep it from the kid".
- The kid prompt keeps its function name (`omarchy_prompt_password`) and variables, since the ISO and first boot both call it. It takes an optional `kid` mode argument: child callers run `omarchy_prompt_password kid`, which relabels it `Kid password> ` and changes the placeholder to "Used for login, unlocking, and disk encryption when enabled". Without the argument it is unchanged, since on a "Me" install the one password still is user, root, and disk.
- Update the header comment: the new variables, and the note that Ctrl+C on the keyboard screen is no longer the ISO's entry into deferred provisioning.

### 2. Profile plumbing

- `bin/omarchy-apply-system --profile <default|child>` (default `default`). It writes `/etc/omarchy/profile` (mode 644, one word) and exports `OMARCHY_INSTALL_PROFILE` for the leaves. `--defer-provisioning --profile child` is accepted and records the profile for the first-boot form to honor (see §6 and the open questions).
- `bin/omarchy-profile-child`: `# omarchy:summary=Succeed when this is a child install`, group `profile`, quiet exit-code predicate in the `hw-` tradition, reading the marker. `GROUP_DESCRIPTIONS[profile]="Install profile detection"`. Menu `when` guards and scripts use it; nothing parses the file elsewhere.
- `install/omarchy-child.packages`: shipped empty apart from a header comment. The ISO vendors it beside `omarchy-base.packages` and adds it to the offline mirror and to `_runtime_package_list` on child installs (§ISO), so phase 1 adds apps by editing one file.

### 3. `bin/omarchy-parent`

Metadata: `# omarchy:summary=Parental controls for child installs`, `# omarchy:args=<password|apply> [--user NAME]`, `# omarchy:examples=sudo omarchy-parent password | omarchy parent password`, `# omarchy:requires-sudo=true`. `GROUP_DESCRIPTIONS[parent]="Parental controls for child installs"`. Runs as root: when `EUID != 0` it re-execs itself under `sudo`, forwarding the caller's `GUM_*` styling the way `omarchy-system-factory-reset` does, so `sudo omarchy-parent password` and the menu's plain `omarchy-parent password` both work, and the elevation prompt itself is the parent-password gate. Outside the child profile it prints "This is not a child install" and exits 1.

`password` — set or change the parent password:

1. Explain what the password gates. `gum input --password` twice; reject blank and mismatch.
2. `printf '%s:%s\n' root "$new" | chpasswd`. Passwords travel over stdin only, never argv.
3. Run `apply --user <kid>` (below) so a machine that somehow lost its drop-ins gets them back. The kid is the account that invoked sudo (`SUDO_USER`), or `--user`.
4. Say that sudo and system prompts now ask for the parent password. It does not touch LUKS: the disk keeps whatever parent slot it has, and _Update > Password > Drive Encryption_ (`omarchy-drive-password`, `luksChangeKey`) rotates any one slot by its current passphrase. The manual explains that two-step.

`apply --user NAME` — the plumbing, hidden from the menu, called by the install leaf, by first-boot provisioning, and by `password`. Modelled on `bin/omarchy-apply-lock`: quoted heredocs (so `test/shell.d/privileged-heredoc-test.sh` stays clean) and idempotent.

- Refuse when root has no usable password (`passwd -S root` not reporting `P`): with `rootpw` in place a locked or empty root makes sudo unusable for everyone. Every caller sets root first.
- Write `/etc/sudoers.d/omarchy-parent` (mode 440): `Defaults rootpw` and `Defaults passprompt="[sudo] parent password: "` with a comment explaining the model and that `NOPASSWD` grants are untouched. Stage to a temporary file, `visudo -cf` it, then install; a sudoers file that fails to parse locks sudo out.
- Write `/etc/polkit-1/rules.d/40-omarchy-parent.rules` (mode 644): `polkit.addAdminRule(function(action, subject) { return ["unix-user:root"]; });` with a comment that it sorts before the package's `50-default.rules`.
- Write `/etc/sudoers.d/omarchy-parent-NAME` (mode 440) holding exactly two lines: `NAME ALL=(ALL:ALL) ALL`, and the browser-accent grant with `NAME` in place of `%wheel`. Same stage-validate-install dance. Also write `00-omarchy-wheel` (`%wheel ALL=(ALL:ALL) ALL`) if absent: harmless with no members, and it keeps `%wheel` meaningful for a future parent account.
- Only then `gpasswd -d NAME wheel` (idempotent when already absent), so there is never a moment without a working sudo path. The group change takes effect at NAME's next login; a running session keeps the group list it logged in with.
- Honor `OMARCHY_SUDOERS_DIR` and `OMARCHY_POLKIT_RULES_DIR` overrides (defaults `/etc/sudoers.d`, `/etc/polkit-1/rules.d`) so the shell test can run it against a scratch tree, in the style of `OMARCHY_PROVISIONING_DIR` and `OMARCHY_DOCKER_SOCKET`.
- `apply --remove [--user NAME]` deletes what it wrote, keeping it reversible. It does not put the account back into `wheel`; that is a deliberate manual step.
- Closes the text consoles: `systemctl mask` on `getty@tty2` through `tty6` (tty1 carries the display manager), with `--now` only on a booted system outside a chroot, which `systemd-detect-virt --chroot` decides since the install chroot sees the live system's `/run`. A kid with her own password could otherwise log in on a console and work outside the lock screen. `omarchy-parent tty on|off` reopens or closes them; `--remove` reopens them. Decided on 2026-09-01 during the screen-time work and kept here because it is posture, not a feature.
- Writes `/etc/omarchy/parent.conf` if absent, with every default spelled out and commented, and `/etc/polkit-1/rules.d/45-omarchy-parent-wifi.rules` from it. Joining or changing a Wi-Fi network is `org.freedesktop.NetworkManager.settings.modify.system` (a per-user profile, `.modify.own`), which NetworkManager's policy leaves at `auth_admin_keep` for an active session; Arch builds NetworkManager with `polkit_noauth_group=wheel`, so a default install never asks while the kid account, outside wheel, asks the parent. The rule pins the choice for the kid account alone and for those two actions only: `polkit.Result.AUTH_ADMIN_KEEP` under `wifi=parent` (the default), `polkit.Result.YES` under `wifi=kid`, so the kid can join the school's network herself. `network-control`, `wifi.scan`, and `enable-disable-wifi` are `yes` for an active session on their own and stay untouched, so known networks, scanning, and the Wi-Fi switch never ask; `modify.hostname` and `modify.global-dns` are not granted, so the DNS whitelist of a later phase keeps its ground. `omarchy-parent wifi kid|parent` edits the file and rewrites the rule, which polkitd reloads on the spot; `omarchy-parent wifi` reports; a hand edit takes effect at the next `apply`. `--remove` deletes the rule and keeps the file. Added 2026-09-01 after the ThinkPad trial, where joining a network asked for the parent password.
- Dispatches feature commands: anything that is not `password`, `apply`, `tty`, or `wifi` is handed to `omarchy-parent-<name>` when such a command exists (`omarchy-parent time on` runs `omarchy-parent-time on`; the `omarchy` router resolves `omarchy parent time on` the same way on its own), ahead of any elevation since each feature handles its own, and `--help` lists the feature commands it finds by their `omarchy:summary`, skipping hidden plumbing. A feature plugs in by adding a binary, never by editing this file, so feature PRs stay independent of each other; `install/helpers/parent.sh` carries `install_sudoers` for all of them. Each feature is off until its own `on`, keeps its state under `/var/lib/omarchy/parent/<kid>/<feature>/`, and removes everything it installed on `off`.

### 4. Install leaf and the timezone menu

- New leaf `install/config/parent.sh`, wired into `install/config/all.sh` after `lockscreen-pam.sh`: when `OMARCHY_INSTALL_PROFILE` is `child` and `OMARCHY_INSTALL_USER` is set, run `omarchy-parent apply --user "$OMARCHY_INSTALL_USER"`; on a deferred child install there is no user yet and first-boot provisioning does it. `omarchy-apply-system` runs the leaf in the ISO chroot after archinstall created the user, so the kid is moved out of `wheel` there, and the leaf's `visudo` check runs against the target.
- `bin/omarchy-menu-timezone` runs a bare `sudo timedatectl` with no terminal, which succeeds only through the `%wheel` grant and otherwise fails silently under `set -e`. Give it the terminal-or-grant-or-`pkexec` elevation `omarchy-dns` uses, so from the kid's session the timezone menu asks for the parent password instead of doing nothing. `test/shell.d/timezone-test.sh` gains the fallback assertion the DNS test already has.

### 5. Lockout for the parent password (`etc/security/faillock.conf`)

Add `even_deny_root` and `root_unlock_time = 120`. `pam_faillock` exempts root by default, so a kid could hammer the parent prompt without ever tripping the 10-try lockout the kid's own account gets. The pam lines `install/config/increase-lockout-limit.sh` rewrites carry `deny=10 unlock_time=120` as module arguments and unspecified options fall through to the config file, so this needs no PAM edit. It ships to every install because the file is an etc-override the `omarchy-settings` scriptlet copies on every upgrade, which would clobber a child-only edit; on a "Me" install nothing authenticates as root except `su`, so it is inert there. Trade-off on child installs: ten wrong tries lock sudo and polkit for two minutes, for the parent too.

### 6. First-boot provisioning (`bin/omarchy-provision-owner`)

Runs the child flow when `omarchy-profile-child` succeeds, which is the state a factory reset of a child machine leaves behind (`/etc` is part of the `@factory` snapshot), or a deferred install that recorded the child profile.

- `user_form`: after `omarchy_prompt_password kid` and before `omarchy_prompt_identity`, a `step "Let's set the parent password..."` with two `say` lines explaining what it gates, then `omarchy_prompt_parent_password || return $?`. Esc unwinds to the keyboard step and Ctrl+C offers the reboot, like the other prompts.
- `confirm_form`: an "Parent password" row. Mask both password rows with a fixed `••••••••` rather than one asterisk per character, so the summary stops leaking lengths.
- `user_groups`: stop seeding `wheel` on child installs; only the groups recorded at install time remain, filtered as today. `useradd -G` and `usermod -aG` must tolerate an empty list (pass the option only when it is non-empty).
- `create_user`: `printf '%s:%s\n' root "$parent_password" | chpasswd` for root and the kid password for the account, then `omarchy-parent apply --user "$username"`.
- `rekey_luks`: add the parent password as a second slot. After `luksAddKey` for the kid, `cryptsetup luksAddKey --key-file "$PROVISIONING_DIR/luks-key" "$device" <(printf '%s' "$parent_password")`; identify both new slots with `--test-passphrase --verbose` the way `new_slot` is found today, and keep both when retiring the throwaway and seller slots. The all-or-nothing rule stays: if either slot cannot be identified or a kill fails, keep the staged key and return 1.
- Nothing new is logged: `run_provisioning` already sends only step names to the log, and neither password ever appears on a command line.

### 7. Polkit dialog copy (`shell/plugins/polkit/`)

- `PolkitModel.js`: `passwordPlaceholder(identityName)` returning "Parent password" for `root` and "Enter password" otherwise. Pure, Node-loadable, tested in `test/shell.d/polkit-test.sh`.
- `PolkitAgent.qml`: read `polkitAgent.flow.selectedIdentity` and its `string` property in `syncFromFlow` into a `currentIdentity` property, guarded (`flow.selectedIdentity ? ... : ""`) so a Quickshell build without the property falls back to today's copy. Use it for the field placeholder. Also require the identity to be the session user (`Quickshell.env("USER")`) before entering `fingerprintMode`: `pam_fprintd` has nothing enrolled for root and falls straight through to the password, so the square sensor card would only flash.
- Verify visually per `agents/skills/visual-verification.md`: `pkexec true` from a terminal shows "Parent password", the kid password shakes the card, the parent password succeeds. Capture both states.

### 8. Fingerprint and FIDO2 wording

Under `rootpw`, sudo and polkit authenticate root, and `pam_fprintd` and `pam_u2f` have nothing enrolled for root, so they fall through to the parent password; the lock screen still takes the kid's fingerprint. Gated on `omarchy-profile-child`: the invitation in `install/user/first-run/setup-fingerprint.hook` says "Unlock with your fingerprint", the closing lines of `bin/omarchy-setup-security-fingerprint` say that sudo and system prompts keep asking for the parent password, and `manual/37-hardware-authentication.md` says the same. FIDO2 only ever covered sudo and polkit, so `bin/omarchy-setup-security-fido2` refuses on a child install with an explanation, and the menu hides _Setup > Security > Fido2_ there. The fingerprint PAM edits stay: harmless now, and correct again on a "Me" install.

### 9. Menu (`default/omarchy/omarchy-menu.jsonc`)

- `"update.password.parent": {"icon":"","label":"Parent","when":"omarchy-profile-child","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy-parent password'"}` beside `update.password.user`.
- `update.password.user` keeps `passwd`, so the kid changes their own login password with their current one; the parent can always reset it with `sudo passwd <kid>`. Optionally relabel it "Kid" on child installs with a second guarded entry; labels themselves cannot be conditional.

### 10. Manual and docs

- `manual/02-getting-started.md`: the first question and its three answers; on Child, the kid password and the parent password and what each does; that both unlock the disk.
- `manual/48-security.md`: "Changing your passwords" gains the parent password; a new "Child installs" section listing what asks for the parent password (sudo, system prompts, updates, installs, the Windows VM and Docker TUI, factory reset, passwordless sudo, the DNS toggle, the timezone menu), that the kid's account is not an administrator, the menu entries, the two-step for rotating the parent LUKS slot, the credential-cache caveat, and the live-USB limitation.
- `manual/51-unattended-installs.md` and the ISO README's autoinstall table: the new `omarchy_install.profile` field and the credentials fields (§ISO).
- `manual/37-hardware-authentication.md`: scope of fingerprint and FIDO2 on child installs.
- `docs/file-layout.md`: the root-side orchestration list gains `parent.sh`; the marker and predicate join the quick reference.
- `default/agents/skills/omarchy/SKILL.md`, Privilege Escalation: one sentence that on child installs `sudo` and `pkexec` ask for the parent (root) password, not the session user's.
- `AGENTS.md` needs nothing beyond the two `GROUP_DESCRIPTIONS` entries.

### 11. Tests (omarchy)

- `test/shell.d/setup-form-test.sh`: the driver prints `computer_for` and `parent_password`; cases for the first question (each answer, Esc, Ctrl+C), the parent prompt (accept, blank, mismatch, same-as-kid with `password` preset, Esc, Ctrl+C), and the kid prompt's `kid` mode, each asserting the prompt returned under `set -e` like the existing cases.
- New `test/shell.d/parent-test.sh`:
  - `omarchy-parent apply --user kid` against scratch `OMARCHY_SUDOERS_DIR`/`OMARCHY_POLKIT_RULES_DIR`, running as a fake root (`unshare --user --map-root-user` when available, the `dns-sudoers-test.sh` pattern, with a skip otherwise), with `passwd -S` and `gpasswd` stubs. Assert the system sudoers file holds exactly the two `Defaults` lines, parses with `visudo -cf` when available, is mode 440 and has no `.` in its name; assert the rules file, loaded under `run_node_test` with a stub `polkit` object, registers one admin rule returning `["unix-user:root"]`; assert the per-account file holds exactly the general grant and the browser-accent re-grant, that `gpasswd -d kid wheel` runs only after it is in place, that a `visudo` failure leaves the account in `wheel`, that a rerun changes nothing, that `--remove` deletes the files, and that a locked root (`passwd -S` answering `L`) makes it refuse before writing.
  - `omarchy-parent password` with scripted `gum` answers (the `GUM_SCRIPT` stub from `setup-form-test.sh`), a `chpasswd` stub that logs stdin, and a profile marker in a scratch root: `chpasswd` receives `root:<new>` on stdin, `apply` runs afterwards, blank or mismatched input never reaches `chpasswd`, and without the child marker it refuses.
  - `omarchy-profile-child` against present, absent, and `default` markers.
  - Static assertions on `bin/omarchy-provision-owner`: `create_user` feeds `root "$parent_password"` and `"$username" "$password"` to `chpasswd`, `user_form` calls `omarchy_prompt_parent_password`, and `rekey_luks` adds the parent key. `create_user` writes `/etc/sudoers.d` by literal path, so it cannot be executed unprivileged the way `user_groups` is in `sudoless-docker-posture-test.sh`.
  - `test/shell.d/sudoless-docker-posture-test.sh` asserts that `user_groups` always includes `wheel`; flip it to assert `wheel` is absent on the child path while the recorded-group filtering still holds.
- `test/shell.d/polkit-test.sh`: `passwordPlaceholder` cases. `test/shell.d/timezone-test.sh`: the fallback assertion.
- `./test/cli` covers the new commands' metadata and the `parent` and `profile` group listings automatically; run `./test/all`.
- New `test/acceptance.d/parent-test.sh` (VM, per `agents/skills/acceptance-tests.md`), skipped unless `omarchy-profile-child` succeeds: with `OMARCHY_ACCEPTANCE_SUDO_PASSWORD` (parent) and a new `OMARCHY_ACCEPTANCE_USER_PASSWORD` (kid) set, `sudo -S -v` rejects the kid password and accepts the parent one; `id -nG` lacks `wheel`; `sudo -n -l -l /usr/bin/omarchy-theme-set-browser-policy 000000` reports `!authenticate` while the DNS grant does not; a `pkexec true` driven through the harness's QMP keyboard captures the "Parent password" dialog, a rejected kid password, and success.

## Design: omarchy-iso

Everything here is against the current `configs/airootfs/root/configurator`, `configs/airootfs/usr/share/omarchy-iso/orchestrator/`, and `bin/omarchy-iso-test`. The repo is not checked out beside this one yet; the acceptance-test guide expects it at `../omarchy-iso`.

### 12. Configurator

- **The first question.** Before `keyboard_form`, a new step runs `omarchy_prompt_computer_for` from the shared form. `other` sets `defer_provisioning=true` and behaves exactly as today's confirmed Ctrl+C: the keyboard and user steps are skipped and the install proceeds to the disk step. `child` sets `profile=child`. `me` sets `profile=default`. The Ctrl+C side channel in `keyboard_form`, its "Press Ctrl+C to prepare this machine for another owner" hint, and `confirm_prepare_for_another_owner` go away; Ctrl+C there becomes the plain `abort` it is on every other screen. The Ctrl+C toggle on the disk screen (unencrypted install) is unrelated and stays.
- **The user step on a child install.** `user_form` calls `omarchy_prompt_password kid`, hashes it as today, then `omarchy_prompt_parent_password` and hashes that too (`parent_password_hash`). The confirmation table gains an "Parent password" row, both rows fixed-masked.
- **`write_user_files`.** `user_configuration.json` gains `omarchy_install.profile` (`default` or `child`; the orchestrator already reads `omarchy_install.defer_provisioning` from that block). On a child install `user_credentials.json` carries `root_enc_password` = the parent hash, the user with `sudo: false` (archinstall then leaves `wheel` alone, and the leaf's `gpasswd -d` is a no-op), `encryption_password` = the kid password as today, and a new `parent_encryption_password` = the parent password in plain text for the second LUKS slot, present only when the install is encrypted, exactly like `encryption_password`. Deferred installs keep their `{"users": []}` shape; a deferred child install (see the open questions) would carry only `omarchy_install.profile`.
- `print_dry_run_files` shows the new field, and `bin/omarchy-iso-configurator` dry runs cover the child path.

### 13. Orchestrator

- `context.py`: `InstallContext.profile` from `omarchy_install.profile`, defaulting to `default`; validate the value. The deferred-provisioning credential scrub keeps `parent_encryption_password` out for the same reason it keeps users out.
- `phases_impl.py`:
  - `_runtime_package_list`: on a child install, append every package from `/usr/share/omarchy-iso/omarchy-child.packages`. `builder/build-iso.sh` vendors that file beside `omarchy-base.packages` and its offline-mirror pruning (`test/unit/test_offline_mirror_pruning.py`) counts it as a package source, so the mirror carries the child set once phase 1 fills the list.
  - New phase, "Adding the parent disk key", between `arch_install_system` and `run_system_finalizer` on encrypted child installs: `cryptsetup luksAddKey <luks device> --key-file <(kid password) <(parent password)`, the device taken from the storage intent's `luks_uuid` the way `_provision_install_encrypted` already does. Fail the install loudly if it cannot add the slot; a child machine whose parent cannot boot it is not finished.
  - `run_system_finalizer`: append `--profile <profile>` to both `omarchy-apply-system` invocations, and add `OMARCHY_INSTALL_PROFILE` to `env_extras` in `_run_target_setup_command` so user-side finalization can key on it later.
  - `configure_login` is unchanged: on an encrypted child install the kid autologs in after typing their LUKS passphrase, and a parent who typed theirs lands in the same session, which is fine because the parent password is what gates root there.
- `omarchy-cidata-load` needs no change: the new fields live inside files it already copies. The README's autoinstall table and `manual/51-unattended-installs.md` document `omarchy_install.profile`, `sudo: false`, `root_enc_password` as the parent hash, and `parent_encryption_password`.

### 14. Test harness and ISO tests

- `bin/omarchy-iso-test`: a `--profile child` run. The installer driver answers the first question with Child (one row down, then Return), types `GUEST_PASSWORD` at "Kid password" and a new `GUEST_PARENT_PASSWORD` at "Parent password", and captures both screens. Every `echo $GUEST_PASSWORD | sudo -S` in the harness (poweroff, the ufw and sshd bootstrap, log collection) goes through a `GUEST_SUDO_PASSWORD` that equals the parent password on child runs and the user password otherwise. The acceptance invocation passes `OMARCHY_ACCEPTANCE_SUDO_PASSWORD=$GUEST_SUDO_PASSWORD` and `OMARCHY_ACCEPTANCE_USER_PASSWORD=$GUEST_PASSWORD`. The first-boot driver (`drive_provision_owner`) gains the same two-password path for a child factory-reset run.
- `test/unit`: a `test_child_profile.py` beside `test_provisioning_state.py` covering `InstallContext.profile`, the credential scrub, `_runtime_package_list` with the child list, and the `--profile` argument to `omarchy-apply-system`; `test_keyboard.py` already reads the shared form from `../omarchy`, and the same candidate list serves a check that the form defines `omarchy_prompt_computer_for` and `omarchy_prompt_parent_password`.
- `test/integration.d/factory-reset-test.sh`: a child-profile variant asserting the marker survives the reset and first boot asks for both passwords.

## Sequencing

Each step is one atomic commit with its tests. The omarchy steps land first because the ISO vendors the form and the package list from the omarchy checkout it is built against (`omarchy-iso-make --local-source ../omarchy ../omarchy-pkgs`).

1. omarchy: shared form — `omarchy_prompt_computer_for`, `omarchy_prompt_parent_password`, the kid prompt label, tests.
2. omarchy: profile plumbing — `omarchy-apply-system --profile`, the marker, `omarchy-profile-child`, the empty child package list, docs.
3. omarchy: `omarchy-parent` with `apply` and `password`, the install leaf, the faillock change, the timezone menu elevation, tests.
4. omarchy: first-boot provisioning on child installs — both passwords, root, the parent LUKS slot, the summary row, `user_groups`, the apply call.
5. omarchy: polkit dialog copy, fingerprint and FIDO2 wording, the menu entry, manual and docs.
6. omarchy-iso: configurator — the first question replacing the Ctrl+C path, the child user step, the credential and configuration fields.
7. omarchy-iso: orchestrator — profile in the context, the child package list, the parent LUKS slot phase, `--profile` to apply-system; unit tests.
8. omarchy-iso: harness — the child run, `GUEST_SUDO_PASSWORD`, the acceptance passwords; then the omarchy acceptance test.

Verify end to end with a fresh ISO built from both checkouts and a child run (`omarchy-iso-make --no-boot-offer --local-source ../omarchy ../omarchy-pkgs`, then `omarchy-iso-test --profile child`), plus a factory reset of that machine to exercise the first-boot path.

## Open questions

1. **"Another owner" of a child machine.** DHH's three answers are exclusive. A rig imaging laptops for a school would want "child, but let the family set the passwords at first boot". The plumbing allows it (`--defer-provisioning --profile child` records the marker and first boot honors it), but the child package set must then be on the target already, which it is, since packages install at ISO time. Recommended: allow the combination in the orchestrator and the cidata path, and keep the interactive question to three answers for now.
2. **Identity prompts for a child.** Decided on 2026-09-02, from PR review: a child install asks for neither the full name nor the email. They only feed git identity and the compose shortcuts, and it is the parent at the keyboard on the child path, so an answer would have been theirs. The hostname prompt stays, with its `omarchy` default: it is what the parent sees on the router, and two kids' machines both named `omarchy` would collide on the home network.
3. **Which passwordless action the kid keeps.** The plan re-grants only the browser-accent write. If even that should prompt, drop the second line from the per-account grant.
4. **Credential caching.** Leave sudo's `timestamp_timeout` alone, since the update pipeline's keepalive depends on it, and document the caveat. Recommended: leave it.
5. **Updates need a parent.** With every root path gated, `omarchy update` waits for a parent. A parent-approved auto-update path is a candidate for `omarchy-parent`.
6. **Root lockout on every install.** `even_deny_root` ships globally because the file is an etc-override. It is inert on "Me" installs, but if that is unwelcome the alternative is a child-only `pam_faillock` argument edit in the install leaf.
