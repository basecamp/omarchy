---
name: omarchy-triage
description: >
  Triage everything new in basecamp/omarchy since the last run — issues and pull
  requests together. Diagnoses each item in its own worktree with an independent
  codex xhigh second opinion, correlates them against each other to find
  regressions, duplicates and competing PRs, pushes fixes straight to
  contributors' branches, and delivers a maintainer report. Designed to run
  unattended on a timer. Use when the user runs /omarchy-triage, asks to triage
  the new issues and PRs, or when a scheduled triage fires.
---

# Omarchy Triage

One pass over everything new in `basecamp/omarchy`: open PRs get reviewed and
fixed, open issues get diagnosed, and then the whole batch is considered
together — because five issues that look separate are often one regression, and
three PRs that look separate are often the same fix.

Built to run with nobody watching. Every rule below about what it may and may
not do exists because an unattended agent has no one to ask.

## Authority

Invoking this skill authorizes, without further asking:

- Creating worktrees, fetching, running tests, committing.
- Pushing fixes to the head branch of a PR under review.
- Writing its own state and report files.

It does **not** authorize, ever, in any mode:

- Merging, closing, reopening, or labelling anything.
- Commenting on issues or PRs, or posting reviews.
- Opening new PRs or pushing to `quattro`/`master`/`dev`.
- Force-pushing anything, anywhere.

Those are the maintainer's. When triage concludes "this should be closed as a
duplicate" or "this needs a comment asking for `omarchy-debug` output", it says
so in the report and stops. The report is the deliverable, not the action.

## Safety on a live machine

This runs on the maintainer's daily-driver Omarchy desktop, possibly while they
are using it. Hard rules:

- Never check out anything in `~/omarchy` — that is the running desktop. All
  work happens in worktrees under `~/.claude/worktrees/triage/`.
- Never install or remove packages, never run `omarchy update`, never run a
  migration against the real `$HOME`. Migrations get exercised in a throwaway
  `HOME=$(mktemp -d)`.
- Never restart the shell or compositor: no `omarchy-launch-shell`, no `qs`, no
  `hyprctl dispatch`, no `systemctl --user restart` of anything.
- Compositor-backed tests only through the lock wrapper (see below).
- Reproducing an issue never means breaking the machine to see if it breaks.
  If confirming a bug requires changing live system state, don't — reason from
  the source and say the reproduction was not attempted.

## Modes

- `/omarchy-triage` — everything new since the last run. This is the timer mode.
- `/omarchy-triage since v4.0.0` — everything opened since that release.
- `/omarchy-triage 6893 6912 7001` — exactly those items, PR or issue.
- `/omarchy-triage issues` / `/omarchy-triage prs` — one side only.

Add `--dry-run` to diagnose and report without pushing any fix.

## State

Lives at `~/.claude/omarchy-triage/state.json`:

```json
{
  "last_run_at": "2026-08-15T13:42:44Z",
  "last_run_status": "complete",
  "seen": {
    "pr-6893":    { "head": "def4ae45", "verdict": "SHIP AFTER FIX", "at": "..." },
    "issue-6976": { "updated_at": "...", "verdict": "NEEDS INFO",   "at": "..." }
  },
  "deferred": [7001, 7002]
}
```

Rules:

- **First run** (no state file): scope to items opened since the latest release,
  not all of history.
- **Re-triage a PR** when its head SHA differs from `seen[].head` — the author
  pushed in response to feedback and it deserves another look. Say in the report
  that this is a re-review and what changed.
- **Re-triage an issue** only if it was reopened, or if it gained a maintainer
  comment since the last pass. Ordinary comment churn is not a trigger.
- **Advance state per item, not per run.** Write each item's entry as its agent
  returns. A run that dies halfway must not skip what it never looked at.
- `deferred` holds items that exceeded this run's cap; they go first next run.

Take a run lock (`flock` on `~/.claude/omarchy-triage/run.lock`, non-blocking)
and exit immediately if another triage is in flight. Two concurrent runs would
double-push.

## 1. Collect

```bash
gh pr list -R basecamp/omarchy --state open --limit 100 \
  --json number,title,author,createdAt,updatedAt,isDraft,baseRefName,headRefName,\
headRepositoryOwner,additions,deletions,changedFiles,maintainerCanModify,mergeable
gh issue list -R basecamp/omarchy --state open --limit 200 \
  --json number,title,author,createdAt,updatedAt,labels,comments
```

Filter against the watermark. Exclude:

- PRs authored by the repo owner (those are "ours", not submissions) unless they
  collide with a community PR — then carry them in as *context* for comparison,
  not as items to review.
- Draft PRs, unless explicitly named in the argument.

## 2. Prioritize and cap

Volume is real: 37 issues and 23 PRs landed in the first day after v4.0.0. An
uncapped run would be enormous and would take hours.

Default cap is **25 items** per run. Fill it in this order:

1. PRs that fix a *confirmed* issue in the same batch.
2. Issues reported against the current release that smell like a regression —
   several independent reports of the same subsystem right after a release is
   the single highest-value thing this skill can find.
3. Remaining PRs, smallest diff first (they finish fast and clear the board).
4. Remaining issues, most-commented first.

Everything above the cap goes to `deferred` and is named in the report — never
silently dropped.

## 3. Set up

Worktrees, one per PR (issues do not need one unless a fix is being drafted):

```bash
BASE=~/.claude/worktrees/triage
git fetch origin "pull/$n/head:triage/pr-$n" --force
git worktree add "$BASE/pr-$n" "triage/pr-$n"
```

**Worktrees share one `.git/config`.** `git remote add` in a worktree writes to
the shared file, so per-PR remotes silently collapse into whichever ran last and
agents push to the wrong repository. Use worktree-scoped config, then verify:

```bash
git config extensions.worktreeConfig true          # once, in the main repo
git -C "$BASE/pr-$n" config --worktree remote.fork.url \
  "https://github.com/<headRepositoryOwner>/omarchy.git"
git -C "$BASE/pr-$n" config --worktree remote.fork.fetch \
  "+refs/heads/*:refs/remotes/fork/*"
git -C "$BASE/pr-$n" remote get-url fork           # must match the PR author
```

`maintainerCanModify: false` means no fix can be pushed — that agent reports only.

Copy `run-shell-tests` from this skill directory to `$BASE/` and `chmod +x` it.
It `flock`s a shared lock and wires `WAYLAND_DISPLAY`/`HYPRLAND_INSTANCE_SIGNATURE`
from the live session, so compositor tests get real coverage instead of silently
skipping. Smoke-test it on one cheap file and confirm the output is not
`no Wayland compositor; skipping` before dispatching anything.

## 4. Dispatch

Copy `pr-protocol.md` and `issue-protocol.md` to `$BASE/`. Give every agent a
short prompt pointing at the right one, plus its assignment and — the part that
actually finds bugs — two to four sentences of area-specific steer:

```
Read <BASE>/pr-protocol.md first and follow it exactly.

- PR: <n> — "<title>"
- Author: <login>
- Size: +X/-Y across N files
- $WT = <BASE>/pr-<n>
- $BASE_BRANCH = <base>
- $HEAD_REF = <head>
- $ITEM = pr-<n>

<the failure mode that would actually hurt a user, the neighbouring code to
compare against, the regression to rule out, any known collision.>
```

Read enough of each diff yourself to write a real steer. "Check the hardware
gate only fires on the intended models" finds bugs; "review this carefully"
does not.

**Pre-wire the collisions.** Before dispatching, scan for PRs touching the same
files, PRs duplicating a maintainer PR, competing implementations of one
feature, and issues an open PR claims to fix. Tell those agents to compare and
report rather than act — choosing between competing PRs is always the
maintainer's call.

The harness caps concurrent subagents (20 by default). Launch to the cap and
dispatch the rest as slots free.

If an agent reports a defect in this harness — wrong remote, clobbered scratch
file, a lock that did not hold — fix it for the agents still running, then audit
whether it already caused damage.

## 5. Consider them together

This is the phase that justifies triaging issues and PRs in one pass. Do it
yourself after the agents return; do not delegate it, because it needs every
result in one head.

Look for:

- **Regression clusters.** Several independent issues against the same
  subsystem, all filed after one release, are one bug wearing five hats. Name
  the suspected commit or PR if the timing points at one.
- **Issue ↔ PR.** Does an open PR already fix this issue? Say so, with both
  numbers, so the maintainer merges once and closes several.
- **Issue ↔ issue.** Duplicates, and the subtler case: distinct symptoms, one
  root cause.
- **PR ↔ PR.** Competing implementations, overlapping migrations, two PRs whose
  migrations both rewrite the same file, or one PR that silently depends on
  another landing first.
- **Coverage gaps between PRs.** Two migrations that each handle part of a
  population and leave a slice covered by neither.
- **Already fixed.** Issues reported against an older version that current
  `quattro` already fixes — check before diagnosing further.
- **Not a bug.** The repo's issue template says verified bugs only, support goes
  to Discord. Support requests and feature ideas get flagged for redirection,
  not diagnosis.

## 6. Act

Fixes get pushed to PR branches per `pr-protocol.md` — defects only, no
rewrites, no scope creep, `Co-Authored-By:` and never a `Claude-Session:`
trailer.

For an issue with a confirmed root cause and a contained fix: prepare the branch
in a worktree, commit it, and **stop there**. Report the branch name and the
diff summary. Opening the PR is the maintainer's call — one PR per body of work,
and an autonomous agent should not be filing them.

Never push anything in `--dry-run`.

## 7. Audit

Before writing a word of the report:

```bash
gh pr view $n -R basecamp/omarchy --json headRefOid --jq '.headRefOid'
```

Every pushed commit must be the live head of the right PR on the right fork, and
every PR nobody touched must still match what was fetched. A push reported as
landed without this check is a lie waiting to happen.

## 8. Report

Write `~/.claude/omarchy-triage/reports/<date>.md`, publish it as an artifact,
and send one desktop notification pointing at it:

```bash
omarchy-notification-send "Omarchy triage" "<n> items — <k> need you"
```

Group by what the maintainer does next, never by number:

- **Needs you now** — blockers, regressions, anything that would ship broken.
- **Merge as-is** — clean PRs.
- **Merge with our fixes** — one line each on what was actually wrong.
- **Blocked** — needs the author, or needs something only the maintainer can do
  (packaging, another repo, a product decision).
- **Decisions waiting** — competing PRs, collisions, retargeting questions.
- **Issues: close / duplicate / redirect** — with the reasoning, ready to act on.
- **Issues: confirmed bugs** — root cause, and the branch name if one is ready.
- **Deferred** — what the cap pushed to next run.

Lead with what would have shipped a broken desktop. Say plainly when something
is clean — a clean PR reported as clean is a useful result. Never manufacture
findings to look thorough on a quiet week; "nothing needs you" is a good report.

Then write state and release the run lock.

## Cautions

- **Verify codex.** It reads control flow confidently and wrongly, and invents
  call sites. Check every claim against source before acting. Record which
  findings were rejected and why — that is signal about both tools.
- **Unique scratch paths per agent.** Concurrent agents sharing a filename
  clobber each other's codex prompts and end up reviewing the wrong item. Always
  `$BASE/reports/<item>.codex-prompt.txt`.
- **Fix, do not rewrite.** A contributor must recognise their PR afterwards.
- **An unattended run reports uncertainty instead of resolving it.** If two
  readings of an issue lead to different actions, say so and let the maintainer
  pick. Guessing quietly is the failure mode that makes autonomous triage
  worthless.
- Worktrees are ~130MB each. Remove them at the end of each run
  (`git worktree remove`) along with their `triage/*` branches, keeping only
  worktrees holding an unpushed fix branch — and list those in the report.
