# Windowing Gate W0 — definition and evidence checklist

This file is the **single** authority on what "W0" means and what evidence it
requires. No session may widen, rename, or re-scope this gate. If a handoff
uses "W0" to mean anything else, that usage is wrong.

## Definition (locked)

W0 is **Phase 1 of the eleven phases in `plans/project-ultimate.md`: a
windowing gate only.** It proves Desktop Mode's window management architecture
on Hyprland. It does **not** mean:

- the product is at a milestone called W0 overall,
- the desktop shell is accepted,
- Windows 7 Ultimate parity exists,
- the OS is shippable.

The product remains **REJECTED** at W0. Overall progress is tracked in
`PRODUCT_DOCTRINE.md` (~15–20% as of 2026-08-23).

## Scope

In scope: Hyprland stays as the compositor; three-button SSD chrome for
server-decorated clients; one-row CSD for CSD clients; minimize / maximize /
restore; LTRB snap with chooser; Alt+Tab; Show Desktop; reopen memory;
click-to-raise; Start click-through dismissal.

Out of scope (never part of W0): Superbar visual polish, wallpaper, branding,
Start feature depth, settings surfaces, agent fabric beyond WindowService,
ISO/installer, forty-task rows other than 20–25.

## Evidence checklist (all required, no exceptions)

GO requires **every** box, witnessed by a dated `HANDOFF_*` file recording
`Accepted W0 tree: <full SHA>` — or an explicit rejection of the gate.

1. [ ] Inspectable commit SHA pushed to GitHub (`work` HEAD).
2. [ ] Clean checkout of exactly that SHA: fresh clone, empty `git status`.
3. [ ] `./test/shell` from the clean checkout: exit code recorded; every
       failing test classified as **env gap**, **known pre-existing**,
       **stale test vs. intended change**, or **regression**. Regressions
       block GO. Anything unclassified blocks GO.
4. [ ] `test/shell.d/monitor-apply-test.sh` green from the clean checkout.
5. [ ] `windows-native-test.sh` full run (numbered 20–25 plus all unnumbered
       proofs) exit 0 against the live metal session.
6. [ ] All three absolute-pointer proofs green:
       `hyprbars-pointer-proof.py`, `csd-caption-pointer-proof.py`,
       `start-dismiss-proof.py`. `/dev/uinput` must be group-writable via the
       shipped udev rule (`etc/udev/rules.d/70-omarchy-uinput.rules`) — never
       a surprise chmod.
7. [ ] Automatic monitor ranking live: `--emit-lua` picks a working desktop
       mode; no pin, no `preferred` fallback.
8. [ ] Human eyes on the glass: the user confirms the physical display shows
       what grim/hyprctl claim. Grim-vs-glass has lied before.
9. [ ] Adversarial source review of the windowing diff, or an explicit
       recorded decision to defer it (deferral caps the verdict at
       "provisionally accepted").

## Anti-representation rules

- An agent writeup is not GO. A transcript is not GO.
- "Done & verified" headers may not contain items that are only claimed.
- Pointer proofs conditional on lucky device permissions do not count.
- The gate cannot grow: if new proof areas matter, they are a new gate, not a
  bigger W0.
