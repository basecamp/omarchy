# Reporting Issues and Upstream Handoff

Use this guide to route support questions, feature ideas, verified bugs, and
requests to change Omarchy upstream.

## Route the Request

- **Support or uncertain cause** — use the Omarchy Discord community: <https://omarchy.org/discord>.
- **Feature idea** — use GitHub Discussions suggestions: <https://github.com/basecamp/omarchy/discussions/categories/suggestions>.
- **Reproducible Omarchy defect** — file a GitHub issue after completing the diagnosis loop in [`troubleshooting.md`](troubleshooting.md).
- **Upstream implementation** — clone or fork the repository and hand control to its `AGENTS.md` as described below.

Routing is complete when the evidence supports the chosen destination; an
unverified symptom remains a support request rather than a bug report.

## File a Bug Report

Start from the escalation artifacts required by [`troubleshooting.md`](troubleshooting.md).
A complete report contains:

- concise title;
- expected and actual behavior;
- minimal reproduction steps;
- Omarchy version and relevant hardware;
- diagnostic log or uploaded log URL;
- a focused screenshot or short recording when the symptom is visual;
- attempted repairs and their results.

Inspect logs and captures for private information before uploading them.

Create the issue with `gh` when available:

```bash
gh issue create --repo basecamp/omarchy --title "..." --body "..."
```

GitHub media attachments must be added through the web form. Save the capture,
inspect it for private information, and give the user its path to attach.

A bug report is complete when it is filed at the correct repository with every
required field supported by gathered evidence. If the user has not authorized
submission, prepare the complete draft and stop before publishing it.

## Hand Off Upstream Development

Source development does not happen in the packaged tree. Create a working copy:

```bash
gh repo fork basecamp/omarchy --clone
cd omarchy
```

Once inside the checkout, read its `AGENTS.md` and every task guide it points to
for the requested area. Those repository instructions govern implementation,
testing, commits, and pull requests. Use the installed-system skill again only
when exercising the resulting change against the user's live Omarchy system.

The handoff is complete when work is in a repository checkout based on the
intended integration branch and the repository's relevant instructions are in
context.
