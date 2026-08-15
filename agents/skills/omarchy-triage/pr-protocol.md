# PR review protocol

You are reviewing exactly one PR to basecamp/omarchy. Everything happens inside your
assigned worktree. Never touch `~/omarchy` itself — that is the maintainer's live
running desktop, and a checkout there breaks their session.

This may be running unattended, with the report read hours later by someone who has
none of your context. Write for that reader: name numbers, files and lines, and never
leave a claim resting on something only you saw.

## 1. Orient

```bash
cd $WT                      # your worktree, given in the prompt
git log --oneline -5
BASE=$(git merge-base origin/$BASE_BRANCH HEAD)
git diff --stat $BASE..HEAD
git diff $BASE..HEAD
```

Read `AGENTS.md` at the repo root and any guide under `agents/skills/` that matches the
area the PR touches (`shell/` → `shell-dev.md`, `bin/` → `command-metadata.md`,
`install/` → `install-scripts.md`, `migrations/` → `docs/migrations.md`). The house
style rules there are binding on any code you write.

Read the *surrounding* code, not just the diff. Most real defects in this repo are
integration mistakes: a helper called with the wrong argument order, a config key that
no reader consumes, a migration that assumes a file exists, a QML property bound to
something that is null on first paint.

## 2. Review it yourself

Hunt for defects that would actually bite a user:

- Correctness: wrong logic, inverted conditions, off-by-one, unhandled nil/undefined.
- Integration: does the rest of the repo actually agree with this change? Grep for
  every caller, every reader of a config key, every other place the same pattern is
  handled. A PR that fixes one of five call sites is a real finding.
- Shell safety: unquoted expansions with spaces, missing `set -e` assumptions, `[[ ]]`
  vs `(( ))` per house style, commands assumed present that are genuinely optional.
- Idempotence: install/ and migrations/ scripts get re-run. Do they survive it?
- Regressions: does this break the non-target hardware/config? Hardware quirk PRs are
  the usual offenders — a fix for one laptop that fires on every machine.
- Dead code, leftover debugging, committed junk files.

Skip nitpicks. Style-only preferences, hypothetical futures, and "you could also"
suggestions are not findings. If it would not change behaviour for a user or a
maintainer, drop it.

Then spend a few minutes on what this PR touches *outside itself*, and put the numbers
in your report's **Related** line:

```bash
gh issue list -R basecamp/omarchy --state open --search "<key terms>" --limit 20
gh pr list -R basecamp/omarchy --state open --search "<key terms>" --limit 20
```

Does it fix an open issue? Does another open PR change the same files, ship a competing
implementation, or add a migration over the same population? Any collision named in
your assignment must be answered explicitly — compare the approaches and say which
covers more, but never edit or close the other PR. Choosing between them is the
maintainer's call.

## 3. Second opinion from codex (required)

Run codex at xhigh reasoning as an independent reviewer. Write the prompt to a file
first — and name that file after your PR, never a shared name like
`scratchpad/codex-prompt.txt`. Sibling agents run concurrently and will clobber it
mid-run, which sends codex off to review someone else's PR:

```bash
cd $WT
REPORTS=~/.claude/worktrees/triage/reports
# write your prompt to $REPORTS/pr-$PR.codex-prompt.txt first
codex exec -c model_reasoning_effort="xhigh" -s read-only \
  -o "$REPORTS/pr-$PR.codex.md" \
  "$(cat "$REPORTS/pr-$PR.codex-prompt.txt")" < /dev/null 2>&1 | tail -40
```

`< /dev/null` matters — without it codex blocks reading stdin. If its output ever
describes a PR that is not yours, the prompt file was clobbered: rewrite it under a
unique name and re-run.

Give codex the real context: the PR title, the base branch, the full diff (or the
command to produce it), and ask it for concrete defects with file:line, not a summary.
Tell it to say plainly when it finds nothing.

Codex is a second opinion, not an oracle. Verify every claim it makes against the
actual source before you act on it — it will confidently invent call sites and misread
control flow. Discard what does not hold up. Note in your report which of its findings
you rejected and why.

## 4. Test

```bash
cd $WT && ./test/cli          # cheap, no lock needed, run it always
```

For anything under `shell/`, or any test in `test/shell.d/`, you MUST go through the
lock — those tests drive the one live compositor and two at once corrupt each other:

```bash
~/.claude/worktrees/triage/run-shell-tests $WT ./test/shell.d/foo-test.sh
```

Pass the specific relevant test files. Only pass no arguments (which runs all 180
files) if your change is genuinely repo-wide. The wrapper blocks until the lock is
free — that wait is expected, do not work around it, do not run `test/shell` or any
`test/shell.d/*-test.sh` file directly, and do not run the graphical acceptance suite.

Never launch `omarchy-launch-shell`, `qs`, or `hyprctl dispatch` yourself outside the
wrapper; the user is working on that desktop.

## 5. Fix

Push fixes for real defects straight to the PR branch:

```bash
cd $WT
# make the edits
git add -A
git commit          # see message rules below
git push fork HEAD:$HEAD_REF
```

The `fork` remote is already configured and points at the contributor's fork. Confirm
it before you push — worktrees share one `.git/config`, so this is set per-worktree and
a wrong value would send your commit to someone else's repository:

```bash
git -C $WT remote get-url fork      # must match the PR author's fork
```

If it does not match, stop and report it rather than pushing.

Rules for fixing:

- Fix defects. Do not rewrite the PR, do not restyle working code, do not expand its
  scope, do not "improve" things the author deliberately chose. A contributor should
  recognise their PR afterwards.
- One coherent change per commit, per `AGENTS.md`.
- Commit message: succinct, describes the change. Body only if the *why* is not
  obvious. End with:

      Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>

  Never add a `Claude-Session:` trailer.
- Comments in code: one or two lines, saying the thing the code cannot say itself.
  Never restate the next line.
- If a defect is real but the fix is a judgement call the maintainer should make
  (architecture, product behaviour, naming of a user-facing thing), do NOT push it.
  Report it instead.
- Do not post comments on the PR. Do not merge, close, approve, or label anything.
- If the push is rejected, do not force-push. Report it.

## 6. Report

Write your findings to `~/.claude/worktrees/triage/reports/pr-$PR.md` and
return the same content as your final message. Keep it tight — this feeds a summary for
the user. Use exactly this shape:

```
## PR <number> — <title>
**Author:** <login>  **Size:** +X/-Y across N files  **Base:** <branch>
**Verdict:** SHIP | SHIP AFTER FIX (pushed) | NEEDS AUTHOR | REJECT
**What it does:** one or two sentences, plain language.

**Findings:**
- [severity: high|medium|low] file.sh:42 — what is wrong and what it would do to a user.

**Pushed:** <commit sha + subject, or "nothing">
**Tests:** <what you ran and the result>
**Related:** <issues this PR would fix, PRs it competes or overlaps with, by number — or "none found">
**Codex:** <what it added beyond your own review; what you rejected and why>
**For the maintainer:** <anything the maintainer must decide, or "nothing">
```

Verdict guidance: SHIP means merge as-is. SHIP AFTER FIX means it is good with the
commits you pushed. NEEDS AUTHOR means a real defect you could not or should not fix
yourself. REJECT means the approach is wrong, not just the code.

Be honest. A clean PR reported as clean is a useful result. Do not manufacture
findings to look thorough, and do not pad the report.
