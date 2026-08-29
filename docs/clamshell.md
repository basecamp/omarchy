# Clamshell display recovery

Clamshell is a laptop with its lid closed and an external monitor active. Omarchy then disables the internal panel, and enables it again when the lid opens or the external monitor goes away. `bin/omarchy-hyprland-monitor-clamshell` does this; it is run by the lid switch bind in `default/hypr/bindings/utilities.lua`, by `omarchy-system-wake`, and by `omarchy-hyprland-monitor-watch` on every monitor add or remove (with retries at 1, 3 and 7 seconds) and every 2 seconds while docked.

This document is the invariant that command is written to, the assumptions it makes about Hyprland, and how each is tested. A change to the command is checked against this document, not against the previous implementation.

## The overlay

The command manages one thing: an overlay, `~/.local/state/omarchy/toggles/hypr/internal-monitor-clamshell.lua`, holding one rule:

```lua
hl.monitor({ output = "eDP-1", disabled = true })
```

`default/hypr/toggles.lua` requires every `.lua` file in that directory, so the overlay is part of the config Hyprland reads on reload, alongside `~/.config/hypr/monitors.lua` and everything `hyprland.lua` reaches. Disabling the panel is placing the overlay and reloading. Enabling it is removing the overlay and reloading: Hyprland re-applies whatever the config says about the panel, at whatever scale, position and mode the user configured, wherever they configured it.

Nothing else is written. Earlier versions also evaluated an explicit `hl.monitor(...)` for the panel after the reload, with a scale read out of `monitors.lua`, and so needed to read that file the way Hyprland does — an obligation no parser closes, since rules also come from `hyprland.lua`, from required files and from toggles. The compositor is the only reader of its own config, and nothing this command does overrides its answer.

## The invariant

- **I1 — authorship.** The only monitor property the command authors is the overlay above. It never authors geometry (scale, position, mode) and never authors `disabled = false`. The overlay is authored only for a known internal name that is safe to write into Lua and into a `hyprctl` argument (`[A-Za-z0-9._-]+`); an unsafe name is refused with exit 1 before any effect, and no overlay is ever authored for an empty name.

- **I2 — the transition relation.** The inputs are the internal name (unsafe, unknown, or known), the clamshell condition, and the manual-disable toggle (`internal-monitor-disable.lua`). Each predicate — `omarchy-hw-clamshell`, `omarchy-hyprland-monitor-external-active` — is read as a tri-state: exit 0 is true, exit 1 is false, a timeout or any other status is unknown. Clamshell is their three-valued conjunction: false if either is false, true if both are true, unknown otherwise. An unknown is never taken for false.

  | internal name | clamshell | manual toggle | desired overlay | the run |
  |---|---|---|---|---|
  | unsafe | any | any | refuse | exit 1 before any effect, hosted helpers included |
  | any | unknown | any | untouched | changes nothing |
  | unknown | true | any | untouched | no name to author an overlay for |
  | unknown | false | any | absent | an overlay does not outlive clamshell, whoever it was for; no wake, since there is no panel to name |
  | known | true | on | untouched | the toggle disables the panel already |
  | known | true | off | exactly the overlay | placed when absent or different |
  | known | false | any | absent | removed when present, then the DPMS wake — unless the manual toggle is on and an external monitor is active or unknown to be |

  Idempotence is defined against this table: where the desired state is *untouched* or *refuse* a run performs no transition, and otherwise a run whose disk state already equals the desired state performs no write, no reload and no dispatch. A run that changes nothing creates nothing either, not even transiently.

- **I3 — one attempt per transition, exact rollback, retry.** A transition is an atomic placement (a uniquely named temporary file in the same directory, then a rename) or removal of the overlay, followed by exactly one bounded `hyprctl reload`. A transition that cannot be made attempts no reload and leaves no debris. If the reload fails or times out, the prior state is put back exactly — whether the file existed, and its exact bytes, kept as a file copy since a shell variable drops trailing newlines — so the next run retries. Nothing is synthesized on rollback.

- **I4 — serialization without loss.** The command takes its own lock, `${XDG_RUNTIME_DIR:-/tmp}/omarchy-monitor-clamshell.lock`, blocking without a deadline, so a lid event queues rather than drops. Every call inside the lock that can reach Hyprland carries a timeout (`OMARCHY_HYPRCTL_TIMEOUT`, 15 s), so a hung compositor cannot hold the lock. The watcher calls the command plainly; it must not take the same lock around it, since the child would then wait on its parent.

The DPMS wake on the enable side is best-effort and not retried: any key or pointer input re-lights the panel.

## Hosted helpers

Before the clamshell branch the command runs `omarchy-hyprland-monitor-internal recover` and `omarchy-hyprland-monitor-internal-mirror recover`, each only when the toggle it exists to recover (`internal-monitor-disable.lua`, `internal-monitor-mirror.lua`) is present. Each acts only when no external monitor is active and its toggle is on, and then turns the toggle off. A helper that fails or times out stops the run before the clamshell branch, since it may have made half of its own transition; the next event or poll runs again. When a stale manual toggle and an overlay coexist, the helper's transition comes first, then the clamshell one: two reloads and two wakes in one locked run.

## What is assumed of Hyprland

- **A1.** `hyprctl reload` rebuilds the monitor rules from the config; rules do not accumulate across reloads.
- **A2.** After a reload whose rules no longer disable a monitor, Hyprland enables it and applies the rule that governs it.
- **A3.** A reload of an unchanged config leaves the panel where it was: scale, position, mode, refresh rate and transform identical, `auto` resolved the same way.
- **A4.** The overlay takes part in the config through `toggles.lua`.
- **A5.** `hyprctl reload` exits non-zero when the reload did not take: no instance, or a config Hyprland rejects.
- **A6.** A headless output can be created under a chosen name, so the internal-panel predicate — the first `eDP|LVDS|DSI` output in `hyprctl monitors all -j` — can be satisfied in a VM without such hardware.

A real Hyprland bringing the panel back in a state that differs from the one it had before the disable is a finding against A2 or A3, and it reopens this document; it does not authorize writing a monitor value.

## Tests

- `test/shell.d/monitor-clamshell-test.sh` (`./test/shell`): T1 reads the command's text — no `hyprctl eval` or `keyword`, no `awk` or `lua`, no `monitors.lua`, a lock; T2 makes both transitions under configs any reader would answer differently and requires the same calls; T3 walks the table above from both starting states with every collaborator stubbed, including the 3×3 predicate matrix, byte-exact rollback, a read-only toggles directory, idempotent runs against a read-only directory, the lock, and every call class hung in turn.
- `test/acceptance.d/clamshell-test.sh` (the disposable VM, run with `--sync-all`, see `agents/skills/acceptance-tests.md`): T4 checks A1–A6 against a real Hyprland with headless outputs standing in for the panel and the external monitor, the hardware predicates stubbed, and a corpus of `monitors.lua` shapes: each transition round-trips and the panel comes back field for field as it was.

A finding that violates I1–I4 or A1–A6 is a defect. A finding about how Lua should be read is, by design, out of scope: the command reads no Lua.
