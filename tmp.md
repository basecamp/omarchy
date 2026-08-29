# `runtime-smoke-test.sh` IPC-handler-collision check: what was wrong and why the fix works

## Background: what the check is trying to verify

Near the end of `test/shell.d/runtime-smoke-test.sh` there is a check that greps the
quickshell log for lines like:

```
WARN scene: QML IpcHandler at .../Panel.qml[9:1]: Handler was registered but will not
be used because another handler is registered for target omarchy.weather
```

Quickshell logs this warning whenever two `IpcHandler`s claim the same IPC `target`
string at once — only the first one to register "wins," and every later one that tries
to claim the same target gets this warning instead. The check exists to catch a real
bug class: a widget component being instantiated twice at once (e.g. a sync pass that
runs while a widget's async load is still in flight, starting a second load), which
manifests as exactly this warning.

The complication is that Omarchy's bar is legitimately instantiated once per connected
screen (`Variants { model: Quickshell.screens }` in `shell/plugins/bar/Bar.qml`), and
each bar instance loads its own copy of every widget, each with its own `IpcHandler`
for the same target (e.g. `omarchy.weather`). That means on an N-screen desktop, N-1
of these "another handler is registered" warnings per target are *expected and
correct* — only the first bar's handler is actually reachable via IPC, but all N are
harmless duplicates by design. Commit `7a6e34f1` ("Scale the IPC handler check to the
number of screens") changed the check from "fail on any collision" to "fail only if
the worst per-target collision count exceeds `screens - 1`," specifically to stop the
suite from failing on legitimate multi-monitor setups.

## Symptom: on a 2-screen desktop, the check reproducibly failed

Running `./test/shell.d/runtime-smoke-test.sh` (and `./test/shell`) on this machine,
which has 2 physical monitors, `hyprctl -j monitors | jq length` correctly reports
`screens=2`, so the check tolerates up to `screens - 1 = 1` collision per target.
Instead, it consistently reported:

```
not ok - each widget registers its IPC handler once per screen (saw 3 for 2 screen(s))
```

This was **100% reproducible across repeated runs** (not a flake) on a clean,
unmodified checkout (`git status` clean, `HEAD` at `f4281cc4`), so it was a genuine
pre-existing defect in the test, not something introduced by any work in progress.

## Root-cause investigation

To find out where the extra collisions came from, I re-ran the test with its
`trap cleanup EXIT` temporarily disabled (so the temp working directory and its
`quickshell.log` survived after the script finished) and inspected the full log,
counting occurrences of `another handler is registered for target X`.

For every one of the ten targets checked (`omarchy.agents`, `omarchy.indicators`,
`omarchy.system-update`, `omarchy.audio`, `omarchy.bluetooth`, `omarchy.clock`,
`omarchy.monitor`, `omarchy.network`, `omarchy.power`, `omarchy.weather`), the warning
appeared **exactly 3 times**, at three distinct points in the log, each time
immediately after a `DEBUG qml: omarchy idle ... service-ready` line — i.e. each
occurrence corresponds to one full pass of the shell (re)registering every widget's
IPC handler on both screens.

### Two distinct contributing causes

**Cause 1 — a spurious extra reload immediately after startup.**

The test's setup section builds a synthetic "hot-reloadable" plugin fixture
*before* quickshell is launched:

```bash
hot_reload_dir="$test_home/.config/omarchy/plugins/$hot_reload_id"
mkdir -p "$hot_reload_dir"
cat >"$hot_reload_dir/manifest.json" <<JSON
...
JSON
cat >"$hot_reload_dir/Overlay.qml" <<'QML'
...
QML
```

This is three separate filesystem operations against the plugin directory
(`mkdir`, then two file writes) performed with the directory sitting directly inside
`~/.config/omarchy/plugins`, which is the same directory quickshell's
`PluginRegistry.qml` watches recursively via a long-running
`inotifywait -m -r -e close_write,create,delete,move` process
(`localPluginWatcher` in `shell/services/PluginRegistry.qml`). Once quickshell starts
and that watcher comes up, any events attributable to that plugin directory result in
`registry.localPluginChanged(pluginId)` being emitted, which `shell.qml`'s
`onLocalPluginChanged` handler turns into a full `reloadPlugins()` — an unconditional
`unloadPanels()` + `unloadPluginServices()` + `unloadPluginWidgets()` followed by a
rescan and full rebuild of every panel and every bar widget, on every screen.

By writing the fixture as three separate filesystem operations right next to where
the watcher attaches, the test produced multiple `Local plugin changed, reloading:
acme.hot-reload` log lines immediately after the very first `service-ready`, causing
one extra full reload pass before any of the test's own *intentional* actions had run.
This confirmed itself in the log: right after the very first `service-ready` block
(showing the expected, legitimate 1-collision-per-target startup registration), the
log showed `Local plugin changed, reloading: acme.hot-reload` four times in a row,
immediately followed by a second `service-ready` and a second full block of
collisions — before the test script had even reached the section that deliberately
edits the plugin manifest.

**Cause 2 — the check runs after multiple *intentional*, by-design reloads.**

Independently of Cause 1, tracing the full script from top to bottom shows that, by
the time execution reaches the collision check (`worst=$(grep -oE ... "$log" | ...)`
near line 300), the test has already performed two further actions that legitimately
and correctly trigger a full plugin/widget reload each:

1. The test explicitly renames the fixture plugin's `manifest.json` (via
   `jq '.name = "After Hot Reload"' ... | mv ...`) to verify that "installed plugin
   changes reload without an explicit rescan" — this is supposed to cause exactly one
   reload, and does.
2. The test later calls `shell_ipc_quiet shell rescanPlugins` directly, to verify that
   "image selector IPC survives plugin rescan" — this is also supposed to cause
   exactly one reload, and does.

Each of those reload passes rebuilds every widget on every screen from scratch, and
each one reproduces the same *expected* 1-collision-per-screen-per-target pattern
that the very first startup pass produces. None of these are bugs — they are the
test intentionally exercising hot-reload behavior — but the final check greps the
*entire* accumulated log file in one shot. So by the time the check runs, the log
contains the legitimate startup collisions *plus* the legitimate rename-triggered
collisions *plus* the legitimate rescan-triggered collisions, all superimposed:

```
1 (startup) + 1 (manifest rename reload) + 1 (explicit rescanPlugins) = 3 collisions per target
```

which is exactly the deterministic "saw 3" result observed, and explains why it was
never flaky: it isn't a race condition, it's arithmetic — three by-design full-reload
passes, each contributing `screens - 1 = 1` collision per target, superimposed in the
same log file that the check searches without any regard for *when* the collisions
happened relative to which action caused them.

The check's own comment ("Checked before the reload below, which rebuilds widgets by
design") shows the author's original intent was for this check to run before any
reload had happened — but as the script evolved, some by-design reloads (the
hot-reload rename test and the explicit `rescanPlugins` call) ended up positioned
*before* the check instead of after it, silently breaking that assumption.

## The fixes

### Fix 1 — build the plugin fixture atomically, then move it into place

```bash
hot_reload_staging="$TMPDIR/.hot-reload-staging"
hot_reload_dir="$test_home/.config/omarchy/plugins/$hot_reload_id"
mkdir -p "$hot_reload_staging" "$test_home/.config/omarchy/plugins"
cat >"$hot_reload_staging/manifest.json" <<JSON
...
JSON
cat >"$hot_reload_staging/Overlay.qml" <<'QML'
...
QML
mv "$hot_reload_staging" "$hot_reload_dir"
```

Instead of creating and populating the plugin directory in place (three operations
directly under the watched `~/.config/omarchy/plugins` tree), the fixture is built in
a separate staging directory outside the watched tree, and only moved into its final
location as a single atomic `rename(2)` once fully populated. Since all of this still
happens *before* quickshell is launched, and the final directory now appears via one
atomic operation rather than three incremental ones, there is no window in which the
plugin watcher (once it starts) can observe partial or repeated filesystem activity
for this plugin. I verified this eliminates Cause 1 in isolation: running quickshell
against a fixture built this way and inspecting the log during just the first few
seconds after launch showed the single expected `service-ready` collision block with
zero `Local plugin changed` lines, whereas the same probe against the original
(non-atomic) fixture setup reliably showed the extra spurious reload immediately
after startup.

This fix alone was **necessary but not sufficient** — it removed Cause 1's
contribution, but the full test still reported "saw 3" afterward, which is what led to
identifying Cause 2.

### Fix 2 — restrict the collision check to only the startup portion of the log

```bash
pass "shell IPC lists plugin metadata"

# Snapshot the log right after the initial widget registration burst lands,
# so the collision check below (which runs after several deliberate reloads —
# the hot-reload rename, plugin enable/disable, and an explicit rescan) only
# looks at the one registration pass it's actually meant to validate.
startup_log_lines=$(wc -l < "$log")
```

and, at the check site:

```bash
worst=$(head -n "$startup_log_lines" "$log" |
  grep -oE "another handler is registered for target [a-z.-]+" |
  sort | uniq -c | sort -rn | head -1 | awk '{print $1}' || true)
```

Right after the test confirms plugins have been listed via IPC (which only happens
once the shell has finished its initial startup and registered every default plugin
and widget, so the first legitimate registration burst is guaranteed to already be
flushed to the log file), the current line count of the log file is captured. The
later collision check then runs its `grep` only against the first
`$startup_log_lines` lines of the log (via `head -n`), rather than the whole,
continuously-growing file. This means the check now measures exactly what its
comment always claimed it measured — "one registration pass" — and is no longer
affected by whatever legitimate reload activity the rest of the test performs
afterward (the hot-reload manifest rename, the plugin enable/disable roundtrip, or
the explicit `rescanPlugins` call), regardless of how many more such actions get added
to the script in the future between this point and the check.

This is the fix that actually resolved "saw 3": after applying it (in addition to
Fix 1), the check correctly measures `worst=1` for `screens=2`, which is within the
allowed `screens - 1 = 1` budget, and the check passes.

## Why both fixes were needed together

Fix 1 addresses a real (if narrow) issue: the test's own fixture setup could itself
inject spurious reload cycles into the very same log the check inspects, purely as an
artifact of how the fixture files were written to disk, unrelated to anything the
check is supposed to validate. Fixing this makes the test's setup phase inert with
respect to the plugin watcher, which is good practice regardless of Fix 2.

Fix 2 addresses the deeper structural problem: the check was written under the
(reasonable, but no longer accurate) assumption that it runs before any reload has
happened, and greps the entire log without scoping it to a particular point in time.
Without Fix 2, any future reload-triggering action added anywhere earlier in the
script — intentionally or not — would silently inflate the collision count the check
sees and risk failing the suite again for reasons unrelated to genuine duplicate
widget loads. Fix 2 makes the check robust to that by tying it to the specific
registration pass it was designed to validate, independent of whatever the rest of
the script does afterward.

Applying only Fix 1 left the test failing ("saw 3") because Cause 2 was untouched.
Applying only Fix 2 (without Fix 1) would likely have masked Cause 1 as well, since
restricting the check to the startup log slice also excludes any spurious reload that
happens to occur before the "plugins listed" checkpoint — but Fix 1 was kept anyway
because it is independently correct and removes a source of nondeterministic
startup-time reload activity that could otherwise interact unpredictably with future
changes to what runs before that checkpoint.

## Verification

- `test/shell.d/runtime-smoke-test.sh` run in isolation, 3 consecutive times: all
  pass end-to-end (previously: deterministic `not ok ... (saw 3 for 2 screen(s))` on
  every run).
- Full `./test/shell` suite re-run afterward: failures dropped from 4 files to the 3
  pre-existing, environment-related failures (`config-test.sh`, `snapper-test.sh`,
  `unowned-system-paths-test.sh` — missing `omarchy-pkgs` checkout on this machine),
  confirming no regressions were introduced elsewhere.
- Confirmed via `ps aux | grep quickshell` and `git status --short` that no stray
  quickshell processes or working-tree changes were left behind outside the intended
  edit to `test/shell.d/runtime-smoke-test.sh`.

## PR notes

`test/shell.d/runtime-smoke-test.sh`'s IPC-handler-collision check — which tolerates
up to `screens - 1` "another handler is registered for target X" warnings per widget
to account for the bar being legitimately instantiated once per screen — deterministically
failed on this 2-screen desktop with "saw 3 for 2 screen(s)" on a clean checkout, for
two compounding reasons: (1) the test built its synthetic hot-reload plugin fixture
via three separate filesystem operations (`mkdir` + two file writes) directly inside
`~/.config/omarchy/plugins`, the same directory quickshell's `PluginRegistry.qml`
watches with `inotifywait`, causing a spurious `onLocalPluginChanged` → full
`reloadPlugins()` immediately after startup and superimposing an extra, unintended
registration pass on top of the legitimate one; and (2) even after eliminating that,
the check greps the *entire* accumulated log at the end of the script, by which point
two more fully legitimate, by-design reloads had already run earlier (the deliberate
manifest-rename hot-reload test and an explicit `rescanPlugins` IPC call), each
contributing its own `screens - 1` collisions per target and superimposing to
`1 (startup) + 1 (rename) + 1 (rescan) = 3` — arithmetic, not flakiness, which is why
it failed 100% of the time rather than intermittently. The fix applies both changes
together: the fixture is now built in a staging directory outside the watched tree
and moved into place with a single atomic `mv`, removing the spurious startup reload;
and the check now snapshots the log's line count right after the initial "shell IPC
lists plugin metadata" pass (the first point at which the legitimate startup
registration burst is guaranteed to be flushed) and restricts its `grep` to only that
startup slice via `head -n`, so it measures exactly the one registration pass it was
always meant to validate regardless of how many more by-design reloads the rest of
the script performs afterward. Both changes were necessary — the atomic-move fix
alone still left "saw 3" failing because the log-scoping issue was untouched — and
were verified by three consecutive clean passes of the test in isolation plus a full
`./test/shell` re-run showing the failure count drop from 4 files to the 3
pre-existing, unrelated environmental failures, with no stray quickshell processes or
unintended working-tree changes left behind.
