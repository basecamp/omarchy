# Task Manager

A system monitor for Omarchy Quattro. One plugin inside the long-running
`omarchy-shell` process, three surfaces sharing one sampler, themed off the
shell palette so it follows `omarchy theme set` without a hard-coded colour
anywhere.

It takes its shape from btop and htop — per-core meters, live rates, a process
table you can sort and signal — and its layout from Dave Plummer's Windows Task
Manager: a graph you read at a glance, a compact mode that stays out of the way,
and a full mode for when you actually need to find something.

## Why

On 17 August 2026 Dave Plummer — who wrote the original Windows Task Manager —
[installed Omarchy for the first time](https://x.com/davepl1968/status/2089409079630606803):

> I installed @dhh's Omarchy - and then realized I'd never touched Arch before,
> let alone Hyprland. […] This is first light on Arch, so there will be a few
> rough edges to sort out, but it works :-)

[Tobi Lütke replied](https://x.com/tobi/status/2089433491171623008):

> We definitely need omatasks

Internally it is **omatask**: plugin id `omarchy.omatask`, IPC target `omatask`,
state in `~/.local/state/omarchy/omatask/`, matching Quattro's Omawrite /
Omacut / Omacalc family. Everything a person reads says "Task Manager".

---

## Surfaces

| Surface | Reached by | Shows |
|---|---|---|
| **Bar widget** | always visible | CPU history graph and current percentage, and optionally a second metric — memory, swap or GPU — beside it |
| **Panel** | click the widget | CPU graph, per-core grid, memory, swap, GPU, network and disk rates, busiest eight processes |
| **Window** | `Expand` in the panel · right-click the widget | Five stat cards that each expand, plus the full process table with filter, sort, threads and signals |

Neither surface claims a keybinding. To bind them, add to
`~/.config/hypr/bindings.lua` — `CTRL+SHIFT+ESCAPE` is the shortcut every other
desktop uses for a task manager, and `SUPER+ESCAPE` is already Omarchy's system
menu:

```lua
o.bind("CTRL + SHIFT + ESCAPE", "Task manager", "omarchy-shell shell toggle omarchy.omatask")
o.bind("SUPER + CTRL + ESCAPE", "Task manager panel", "omarchy-shell omarchy.omatask toggle")
```

## Keys

Everything is reachable from the keyboard alone; the mouse is an alternative,
never the only route. The overlay carries one line of chrome and keeps the full
list behind `?` — which opens the legend only when the filter is empty, since
otherwise it is just a character.

**Panel**

| Key | Does |
|---|---|
| `↑` `↓` / `j` `k` | Move through the rows |
| `x` | Terminate the selected process |
| `Enter` / `Space` | Expand to the overlay |
| `Tab` | Move to the next bar panel |
| `Esc` | Close |

**Overlay**

| Key | Does |
|---|---|
| any character | Filter by name, command, user or pid |
| `Backspace` / `Ctrl+U` | Edit / clear the filter |
| `↑` `↓` · `PgUp` `PgDn` · `Home` `End` | Move the selection |
| `Enter` / `→` | Expand the process into its threads |
| `←` | Collapse it |
| `Del` / `Shift+Del` | Terminate / kill |
| `s` / `c` | Suspend / resume |
| `[` / `]` | Lower / raise priority |
| `Ctrl+O` | Open files and sockets |
| `Tab` / `Shift+Tab` | Cycle the sort column |
| `Ctrl+R` | Reverse the sort |
| `Ctrl+A` | Cycle processes / applications / tree |
| `g` | Group an app's scopes (Applications view) |
| `Ctrl+L` `Ctrl+G` `Ctrl+M` `Ctrl+N` `Ctrl+D` | Expand the CPU / GPU / memory / network / disk card |
| `Ctrl+↑` `Ctrl+↓` | Scroll the expanded card |
| `?` | Key legend |
| `Esc` | Clear the filter, then close |

With the mouse: a row's `✕` terminates on left-click and kills on right-click,
the `▸` chevron expands threads, any card toggles its expanded view, and column
headers sort — clicking the active column flips direction.

---

## The three lists

`Ctrl+A` cycles between them.

**Processes** — the flat table, covering every process on the machine. Its
**wait** column is time spent runnable but not running, from `schedstat`: the
number that explains a machine feeling slow while CPU% reads calm. Under 2×
oversubscription a process here shows 38% CPU against 63% waiting.

**Applications** — grouped by systemd scope. Omarchy launches every app into
its own scope, so the kernel has already grouped processes the way people think
about them; this is the view other Linux monitors struggle with, because it
depends on the desktop registering a cgroup per app. Rows show member count,
aggregate CPU, honest `memory.current` rather than a sum of double-counted RSS,
and **I/O stall** — the share of the interval the app spent blocked on disk.
That last column exists even where per-app I/O *bytes* do not, because PSI is
exposed per cgroup whether or not the io controller is delegated.

**Tree** — the same data with parent/child structure, so forty-seven chromium
processes read as one family.

### How an application is identified

Grouping pulls two ways. One app can own several scopes — Chromium launched
from the menu and Chromium activated through XDG. But different apps can share
a process name: `podcast-worker.service` and `hermes-gateway.service` are both
`python`, and merging on `comm` would fuse two unrelated programs.

So identity comes from the unit, which systemd already made unique:

| Scope | Identity | Example |
|---|---|---|
| `*.service` | the unit name | `podcast-worker` |
| `app-….scope` | the desktop id, minus compositor tag and hash | `org.chromium.Chromium` → `chromium` |
| `docker-…`, `libpod-`, `machine-` | the container id, labelled from inside | `mongod (1111aaaa)` |
| launcher or tmux scope | the heaviest process inside | `app-Hyprland-gtk-launch-…` → `slack` |

Two `mongo:7` containers are two databases, so they stay two rows. Press `g` to
see the raw scopes instead.

---

## Expandable cards

Each stat card opens into what that resource actually decomposes into, which is
different for each. They are mutually exclusive. Detail columns clip and scroll,
growing a scrollbar only when there is something to scroll to.

### CPU — `Ctrl+L`

One history graph per logical core. Each core keeps its own ring whether or not
the view is open, so it opens showing the last two minutes. Cells shrink to fit
the core count before resorting to scrolling; 32 threads land in three rows.

Below: CPU and GPU temperature graphs, every hwmon sensor the kernel exposes,
and fans. Sensor names are translated from driver names to hardware — `k10temp`
→ CPU, `spd5118` → DIMM, `mt7921_phy0` → WiFi — and where two devices report
the same sensor the *device* is numbered, so a pair of drives reads
`NVMe 1 Composite` / `NVMe 2 Composite`.

Temperature graphs use a fixed 30–100 °C scale with a dashed line at 90 °C
rather than autoscaling, which would turn a degree of idle jitter into a
mountain range. Crossing the line turns the trace urgent.

### Memory — `Ctrl+M`

- **Graphs** — used, swap used, and *processes against page cache on one shared
  scale*. Anonymous memory climbing while cache is squeezed out is the shape of
  a machine running out of room, and only visible when the two are plotted
  together.
- **Where it went** — process memory, shared/tmpfs, slab (reclaimable vs
  locked), page tables, kernel stacks. "22 GB used" hides that ~4 GB of it is
  kernel slab. Reclaimable page cache is listed apart, because it is not "used"
  in any sense worth alarming about.
- **Pressure** — PSI stall percentages for memory, CPU and I/O. A memory bar at
  90% may be healthy page cache; `some avg10` above zero means tasks *actually
  stalled waiting*.
- **Swap, DIMM temperature, commit** — swap areas with priority; for zram the
  algorithm, what it holds, the ratio and the RAM saved. `Committed_AS` against
  `CommitLimit`, stated rather than alarmed about, since overcommit is normal.

### GPU — `Ctrl+G`

A graph per engine (graphics, encode, decode), the hardware readouts — VRAM, SM
and memory clocks, fan, power against its enforced limit, PCIe throughput — and
**VRAM by process**. Any counter the driver declines to report is omitted
rather than drawn as a confident zero.

| Vendor | Source |
|---|---|
| NVIDIA | NVML through `ctypes`; ~0.15 ms per sample, no `nvidia-smi` fork |
| AMD | `amdgpu` sysfs — no engine or per-client queries exist there, so those rows are absent |

### Network — `Ctrl+N`

- **Graphs** — down, up, and **wifi signal in dBm**, on an inverted temperature
  graph with the line at −70. Signal is the one network reading that is a
  *condition* rather than a rate: throughput can be zero because nothing is
  being asked for, but a sagging dBm is always a fact about the link.
- **Links** — state, negotiated speed and duplex, MTU, wifi quality, and each
  interface's own throughput rather than only the total.
- **Errors and drops** — since-boot counters, urgent when non-zero, labelled as
  counters so a large lifetime number is not read as a live problem.
- **TCP sockets** — counts by state.

Interfaces are filtered twice: container plumbing (`veth*`, `br-*`, `docker*`)
double-counts the physical link beneath it, and a link with no carrier is
excluded — an unplugged NIC still appears in `/proc/net/dev` with frozen
counters, and listing it as active is a small lie.

### Disk — `Ctrl+D`

- **Graphs** — read, write, and *busiest device utilisation*. Throughput says
  how much is moving; utilisation says how hard the device is working to move
  it. A drive can sit at 100% util shifting very little.
- **Devices** — throughput, IOPS, %util, queue depth and mean request latency,
  from the extended `/proc/diskstats` fields. This is iostat's data.
- **Filesystems** — usage per *filesystem*, not per mount: a btrfs pool with
  subvolumes at `/`, `/home` and `/var/log` is one thing to run out of. The
  percentage matches `df`'s Use%, measured against spendable space so ext4's
  root reserve is not counted as free.
- **I/O by process** — which processes are touching the block device.

---

## Threads, files and actions

Expanding a process lists its threads with per-thread CPU, busiest first, from
`/proc/<pid>/task/`. One process is expanded at a time and the sampler only
walks task directories while one is. Single-threaded processes show no
disclosure.

`Ctrl+O` lists a process's open files and sockets — "what is holding this port",
"why can't I unmount this" — resolved by joining socket inodes against
`/proc/net/tcp`.

Beyond signals, a process can be renice'd (`[` `]`), suspended and resumed
(`s` `c`), and pinned to a CPU set. Priority changes try unprivileged first and
escalate through `pkexec` only when the kernel refuses, so lowering priority —
which needs no privilege — never raises a dialog.

**CPU percentages are per-core**: 100% is one core saturated, so the ceiling is
core count × 100. A row is drawn urgent by its *share of the machine* rather
than a fixed number, because a fixed threshold means a sixtieth of a 32-thread
desktop and an eighth of a 4-core laptop.

---

## Alerts — off until you ask

Disabled by default. A monitor that starts pushing notifications the moment it
is installed is making a decision that belongs to the person running it, and a
disk you filled on purpose does not need telling you about.

Enable in `Setup > Plugins`, or:

```json
{ "id": "omarchy.omatask", "alerts": true }
```

Once on, alerts go to the shell's own notification daemon: a filesystem past
95%, sustained memory stall, a CPU at its thermal limit, btrfs metadata
exhaustion or device errors, and failed systemd units. Each latches on the way
up and clears on the way down, so a value flapping around a threshold cannot
spam.

## Settings

Per bar-widget entry in `~/.config/omarchy/shell.json`, or through
`Setup > Plugins`.

| Key | Default | Meaning |
|---|---|---|
| `intervalSec` | `2` | Seconds between samples |
| `historyPoints` | `60` | Samples kept for the graphs — 60 × 2s is two minutes |
| `processLimit` | `60` | How many command lines are resolved (not how many processes are listed) |
| `showPercent` | `true` | Percentage beside each bar graph |
| `barGraph` | `"sparkline"` | `sparkline`, `bars`, or `none` |
| `secondaryMetric` | `"none"` | A second reading in the bar beside CPU: `mem`, `swap`, `gpu`, or `none` |
| `alerts` | `false` | Desktop notifications |
| `groupApps` | `true` | Fold an app's scopes into one row |
| `listMode` | `"processes"` | Which list the overlay opens on |
| `sortBy` | `"cpu"` | Sort column |
| `sortDescending` | `true` | Largest first |

## What is remembered

A preference is how you like the tool; transient state is what you happen to be
doing. The first survives a shell restart, the second does not — a filter that
came back after an `omarchy update` would be a bug.

| Remembered | Deliberately not |
|---|---|
| List mode, grouping, sort column and direction | Filter text, selected row |
| Everything in the settings table | Expanded process, expanded card |
| Recorded history | The key legend |

Preferences write back to the widget's `shell.json` entry, so the keyboard and
`Setup > Plugins` never disagree. Values equal to the default are omitted, so
the config records only actual choices.

---

## How it works

```
sampler.py ──JSON lines──> Service.qml ──┬──> BarWidget.qml  (bar + panel)
 (one python3; /proc, /sys,   history,   └──> Overlay.qml    (full table)
  cgroups, NVML)              rates, gates
```

`Service.qml` is the plugin's `service` entry point, so the shell mounts exactly
one and hands the same instance to both surfaces. History lives there, which is
why graphs are populated the moment a surface opens.

`sampler.py` runs for the life of the shell and emits one JSON object per
interval, holding the previous `/proc` snapshot in memory so every CPU figure is
a true delta rather than the since-boot average `ps` reports. Commands arrive on
stdin (`interval`, `procs`, `apps`, `gpu`, `sensors`, `netdetail`, `diskdetail`,
`sockets`, `openfiles`, `threads`, `history`, `quit`), so changing a setting or
opening a view never restarts it and never interrupts the history.

### Paying only for what is on screen

Every expensive reading is collected only while something displays it.

| Reading | Cost | Collected when |
|---|---|---|
| Everything always-on | **1.5 ms** | always |
| Process table | ~14 ms | the panel or overlay is open |
| Application cgroups | ~10 ms | the Applications view is open |
| Off-CPU hwmon sensors | ~23 ms — NVMe admin commands, DIMM I²C, wifi firmware | the CPU, memory or disk card is expanded |
| GPU PCIe + per-client VRAM | ~41 ms — NVML samples PCIe over a fixed window | the GPU card is expanded |
| NIC errors + socket table | ~4 ms | the network card is expanded |
| Per-process block I/O | ~1.3 ms per 60 processes | the disk card is expanded |
| Thread list | one `task/` walk | a process is expanded |

The NVIDIA driver is not mapped at all until a GPU surface opens, which costs
~31 MB of RSS and 0.8 ms per sample. At rest the sampler measures **0.00% CPU
and about 6.6 MB RSS**.

### Flight recorder

History is appended to `~/.local/state/omarchy/omatask/history.jsonl`, roughly
400 KB per day at a 30 s tick, and replayed at startup — so the graphs survive
`omarchy update` and can answer "what happened at 3am".

This is fixed-tick sampling, the model zenith uses. It is deliberately not
atop's: atop hooks BSD process accounting and can attribute a process that both
started and exited between two samples. Nothing here sees such a process.

---

## Limits

Things a monitor might reasonably want that this machine will not give up.

| Wanted | Blocker |
|---|---|
| Per-process network bytes | No per-process network accounting exists in `/proc`. Needs eBPF or packet capture, as `nethogs` does. Per-process *connections* are shown instead |
| Per-process PSS | `smaps_rollup` costs ~0.39 ms per process; RSS double-counts shared pages, so the memory column overstates a browser |
| CPU package watts | `energy_uj` is root-only — the PLATYPUS mitigation |
| NVMe SMART / wear | Needs `NVME_IOCTL_ADMIN_CMD` and `CAP_SYS_ADMIN` |
| Fan RPM | Needs a super-I/O driver; MSI B650 boards want the out-of-tree `nct6687d`. The GPU fan comes from NVML and is unaffected |
| Per-app I/O bytes | `io.stat` needs `Delegate=…io` on `user@.service`. Docker already delegates it, so containers have it today |

Two of these are stated in the UI rather than left to be discovered:
per-process disk I/O reports how many processes it could read (`/proc/<pid>/io`
is owner-only — typically a few hundred of several hundred), and the network card says outright that
per-process bandwidth is unavailable.

## Tests

```bash
python3 test_sampler.py
```

Fifty-seven checks over the parsers and derivations, on fixture strings rather
than live `/proc`, so the suite is deterministic. The parsers are what deserve
testing: a sampler bug is silent by nature — a mis-parsed field surfaces as a
plausible-looking wrong number, not a crash. Mutation-checked; breaking the
latency divisor or making PSI read `full` instead of `some` both fail it.

## Development

Run `omarchy-restart-shell` after editing any QML here. Saving can appear to
hot-reload, but both that and `omarchy-shell shell rescanPlugins` may still
serve a **cached compiled QML type** for a file whose contents changed — if an
edit stubbornly refuses to take effect, restart the shell before assuming the
edit is wrong.

```bash
journalctl --user -f | grep omatask                      # errors
omarchy-shell omarchy.omatask open|close|toggle|expand   # the bar panel
omarchy-shell shell toggle omarchy.omatask               # the window
./test/shell                                             # includes the sampler suite
```
