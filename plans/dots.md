# Plan: Dots — preserve and sync user configs out of the box

Revision 3. Rev 2 incorporated adversarial review by codex (xhigh) and grok;
rev 3 names the feature **dots** (`omarchy dots ...`) and adds the
multi-machine sync design.

## Problem

Omarchy declares `~/.config` "your files" but does little to preserve them:

- `omarchy-refresh-config` litters `*.bak.<timestamp>` files next to originals.
- `omarchy-reinstall-configs` clobbers everything back to `/etc/skel` defaults.
- Snapper only snapshots the `root` config; recovering one config file from a
  root snapshot is not a workflow, and `/home` may not be covered at all.
- The manual punts to a YouTube video about Stow.

There is no way to answer "what did the last update change about my configs?",
"restore my bindings from last week," or "make my new laptop feel like my
desktop."

## Rejected approaches

- **`git init ~/.config`**: dumping ground — Chromium profile, fcitx5 state,
  app tokens, machine churn. A `.git` there gets discovered by editors and
  prompts. Can't cover `~/.bashrc` or `~/.XCompose`.
- **`~/.config/omarchy` only**: too narrow; misses hypr, terminals, `.bashrc`.
- **Stow**: inverted model requiring file migration; organization, not history.
- **chezmoi / yadm**: third-party DSLs we'd be wrapping; overkill.
- **Raw git passthrough / lazygit over `$HOME`** (rejected in review):
  `git clean -fd`, `reset --hard`, or "stage all" against a `$HOME` work tree
  is a home-directory-eraser; `git add -A` can ingest `~/.ssh` and the object
  store into itself (`status.showUntrackedFiles no` only affects `status`);
  `remote add` + `push` silently defeats local-only. Experts can construct the
  raw invocation themselves; Omarchy will not bless it.
- **Distributed git across machines**: two machines auto-committing timer and
  update snapshots into a shared branch conflict constantly. History and sync
  are different products (see Sync below).

## Chosen design: bare repo over `$HOME`, driven only by constrained commands

```bash
git init --bare ~/.local/share/omarchy/dots.git   # mode 0700
```

No `.git` in any directory tools walk; files stay plain files in place. All
access goes through one internal helper that runs git **hermetically**:

- Repo-local config only: synthetic identity (`Omarchy <omarchy@localhost>`),
  `commit.gpgsign=false`, `core.hooksPath` disabled, `--no-verify`,
  `GIT_CONFIG_GLOBAL=/dev/null` so user signing/hooks/templates/excludes and a
  `$HOME/.gitignore` can never break or intercept an automatic commit.
- Never export `GIT_DIR`/`GIT_WORK_TREE` (would leak into `omarchy-plugin-*`,
  `omarchy-theme-update`, `omarchy-update-dev`, user hooks).
- Serialized via a lock; concurrent refresh/update/manual snapshots queue.
- **Best-effort everywhere**: a failed snapshot warns and continues. History
  is optional; updates are not. Never on the failure path of
  `omarchy-update`/`omarchy-migrate` (`set -e` there must not see git errors).

### Audited manifest, not a derived whitelist

Tracking is `git add -f --pathspec-from-file=<manifest>` only. The manifest is
a hand-audited file shipped with Omarchy — explicitly **not** derived from
`$OMARCHY_PATH/config` (which ships Chromium Preferences, fcitx5,
`opencode/opencode.json` where users put API keys, etc.):

- Include: `.config/hypr/*.{lua,conf}`, `.config/omarchy/shell.json`,
  `.config/omarchy/extensions/**`, `.config/omarchy/hooks/**`,
  terminal configs (alacritty/foot/ghostty/kitty), `.config/btop/btop.conf`,
  `.config/starship.toml`, `.bashrc`, `.XCompose`.
- Exclude (deliberately): `.config/omarchy/plugins/**` and
  `.config/omarchy/themes/**` (nested git clones managed by
  `omarchy-plugin-*` / `omarchy-theme-update`), backgrounds (multi-MB
  binaries), `.config/btop/themes/` (symlink into `~/.local/state`), anything
  Chromium/fcitx5/opencode/xournalpp.
- **Two tiers**: every manifest path is history-tracked, but some are marked
  `local` — machine-specific files that sync must never touch. At minimum
  `monitors.lua`; likely hardware quirks like `dell-haptic.conf`. This is the
  lightweight answer to chezmoi's hostname templates: exclude, no DSL.
- Once committed, a secret lives in the object store forever; "no remote" is
  not a secrets story. The manifest is the deny line — nothing outside it is
  ever staged, and there is no command that stages more.

### Dotfile-manager detection: stand down, don't fight

`manual/31-dotfiles.md` sends users to Stow today, and migrations deliberately
write *through* symlinks. For those users git records an unchanged symlink, so
snapshots would be silent no-ops — and `restore` could stomp a symlink with a
regular file. Therefore:

- At seed time and before each snapshot: if manifest paths are symlinks or a
  known manager (yadm, chezmoi, existing bare-repo alias, `~/.git`) is
  detected, mark the repo dormant and say so in `omarchy dots status`.
- `restore` refuses type changes (symlink↔file) and paths outside the
  manifest.
- These users keep `.bak` behavior, which genuinely works for them (copies
  content, not links).

### Snapshot points: batch boundaries, before *and* after

The unit is a labeled snapshot pair around each *batch* mutation, via an
internal `omarchy-dots-snapshot "<label>"`:

1. **`omarchy-provision-user`**: seed repo + initial commit, after `git.sh`
   and `.XCompose` are in place. Idempotent; `--force` must not re-init.
2. **`omarchy-migrate`**: before/after pair labeled with version. Covers both
   `omarchy-update` *and* the login-time migration path, and separates
   migration changes from prior user dirt — the "before" commit captures user
   edits, the "after" commit is purely what migrations did.
3. **Batch refresh commands** (`omarchy-refresh-hyprland` etc.): one pair per
   command, not one commit per `omarchy-refresh-config` call (hyprland calls
   it seven times).
4. **`omarchy-reinstall-configs`**: a "before" snapshot — honestly labeled.
   This operation replays all of `/etc/skel`; a manifest repo does **not**
   make it reversible and we don't claim it does.
5. **Timer**: an hourly-ish systemd user timer committing only if dirty, so
   hand edits are captured — without it, "restore my bindings from last week"
   fails for any edit not followed by an Omarchy operation.

`.bak` files **stay** in v1. They serve symlink users, they're documented
(manual, agent skill, `refresh-config-test.sh` asserts them), and git history
is invisible until the menu surface exists. Removal is a later, separate
decision once restore is on *Update > Config* and proven.

## Sync across machines: publish/pull of state, not history

The local snapshot history is machine-generated noise (timer commits,
before/after pairs) and stays private. Sync happens on a shared `sync` branch
in the same repo that only two operations touch:

- **`omarchy dots push`** — *squash-publishes* the current manifest state
  (minus `local`-tier files) as one commit: "Published from <hostname>". Only
  present-state files leave the machine — a token the timer captured last
  month and you since deleted is not in any published commit.
- **`omarchy dots pull [url]`** — fetches `sync`, takes a local pre-pull
  snapshot (so pull is undoable via `restore`), then applies the files.
  Never touches `local`-tier files. With a URL argument on a fresh machine,
  it configures the remote first — the second-machine straight shot is one
  command.

Conflict story stays simple because publishes are whole-state: push refuses
when the remote moved since your last pull ("pull first"); pull attempts a
per-file three-way merge and falls back to taking remote — your version is
one `omarchy dots restore` away.

Remote setup UX:

- `omarchy dots push` with no remote runs setup inline: paste a git URL, or
  create a **private** GitHub repo via `gh` when authenticated. Verify the
  repo is private; warn loudly if not.
- Manual by default. Push is an intentional "my setup is good" moment — no
  auto-push ever (publishing half-finished experiments is an anti-feature).
  Opt-in *pull on login* later for people with one canonical machine; safe
  because every pull is snapshot-guarded.
- Dormant mode (dotfile-manager users) disables sync too — they have their
  own.
- v2 candidate: `omarchy-provision-first-run` asks "Got a dots repo?" so a
  new machine is yours before first login completes. Held back from v1 —
  drags SSH/auth bootstrapping into first-run.

## User-facing surface (v1)

Constrained commands only — a new `dots` group in `GROUP_DESCRIPTIONS`,
invoked as `omarchy dots <verb>`:

- `omarchy dots snapshot [label]` — take a snapshot now
- `omarchy dots log` — history with labels
- `omarchy dots diff [ref]` — default range: the last before/after pair
- `omarchy dots restore <file> [--at <ref>]` — accepts `~/.config/...`,
  `.config/...`, or manifest-relative paths; takes a pre-restore snapshot
  first so restore is itself undoable; refuses untracked paths and type
  changes; confirms over dirty files
- `omarchy dots push` / `omarchy dots pull [url]` — sync (above)
- `omarchy dots status` — repo state, dormant/active, remote, last
  snapshot/publish

No raw git surface. No lazygit integration.

## Rollout

- New users: seeded by `omarchy-provision-user`.
- Existing users: migration inits the repo + initial commit — **skippable and
  bounded**: no-op if repo path exists, another manager is detected, or
  identity can't be synthesized; never adds beyond the manifest; never fails
  `omarchy update`.
- Docs/tests alignment: manual `31-dotfiles.md` gets the built-in story
  (honest framing: local event history + sync of published states, *not* a
  backup — the local repo dies with the disk); a `docs/dots.md` reference doc
  per the documentation layout; `default/agents/skills/omarchy/SKILL.md`
  updated; CLI routing/metadata tests extended; new tests for identity-less
  commit, batch snapshot pairing, restore round-trip, dormant-mode detection,
  push/pull round-trip against a local bare remote, `local`-tier exclusion,
  and "git failure must not fail update".

## Open questions

1. Manifest location: `default/omarchy/dots-manifest` vs alongside the
   helper; and whether users may extend it via
   `~/.config/omarchy/dots-manifest.d/`.
2. Whether `.config/omarchy/hooks/**` belongs in the manifest at all (small
   scripts, but the likeliest place for a pasted token).
3. Harden `omarchy-refresh-config` against `..` path escape (documented today
   in AGENTS.md) as part of this work or separately.
4. Timer cadence (hourly vs daily) and whether the dirty-check should debounce
   against an active editing session.
5. Whether `input.lua` is `local`-tier (keyboard layouts travel, trackpad
   quirks don't).
