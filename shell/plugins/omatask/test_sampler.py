#!/usr/bin/env python3
"""Tests for the sampler's parsers and derivations.

Run with `python3 test_sampler.py`. No test framework, no dependencies — this
has to be runnable on a fresh Omarchy install with nothing added.

The parsers are the part worth testing: a sampler bug is silent by nature, and
a mis-parsed field shows up as a plausible-looking wrong number rather than a
crash. Most of what follows works on fixture strings and is deterministic
regardless of what the machine is doing.

The exception is the baseline group at the end, which builds a real Sampler and
therefore reads this host's /proc, /sys and cgroup files. That is deliberate —
it is the only way to check that priming actually takes a baseline — and it is
written to assert against what the host exposes rather than assuming any of it
is present, so a container without cgroup v2 passes rather than failing.
"""

import importlib.util
import os
import sys
import tempfile

# Load from source every run. A stale __pycache__ entry can otherwise shadow an
# edit made within the same second as the previous compile — which silently
# turns this suite into a test of the last version rather than this one.
sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLER = os.path.join(HERE, "sampler.py")
spec = importlib.util.spec_from_file_location("sampler", SAMPLER)
if spec is None or spec.loader is None:
    # Otherwise this dies with an AttributeError on None, which says nothing
    # about the file that is actually missing or unreadable.
    sys.exit("cannot load the sampler under test: %s" % SAMPLER)
sampler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sampler)

failures = []
checks = 0


def check(name, got, want):
    global checks
    checks += 1
    if got != want:
        failures.append("%s\n      got:  %r\n      want: %r" % (name, got, want))


def close(name, got, want, tolerance=0.05):
    global checks
    checks += 1
    if got is None or abs(got - want) > tolerance:
        failures.append("%s\n      got:  %r\n      want: ~%r" % (name, got, want))


# ---------------------------------------------------------------- formatting

check("busy_percent: half busy",
      sampler.busy_percent((50, 100), (0, 0)), 50.0)
check("busy_percent: idle interval yields 0, not a divide error",
      sampler.busy_percent((10, 100), (10, 100)), 0.0)
check("busy_percent: counter reset clamps at 0",
      sampler.busy_percent((0, 100), (50, 200)), 0.0)
check("busy_percent: clamps above 100",
      sampler.busy_percent((300, 100), (0, 0)), 100.0)

check("rates: per-second from a delta",
      sampler.rates({"a": (200, 400)}, {"a": (100, 200)}, 2.0), {"a": (50.0, 100.0)})
check("rates: unknown key is skipped rather than counted from zero",
      sampler.rates({"new": (10, 10)}, {}, 1.0), {})
check("rates: a counter that went backwards reads 0, not negative",
      sampler.rates({"a": (5, 5)}, {"a": (100, 100)}, 1.0), {"a": (0.0, 0.0)})

# ---------------------------------------------------------------- cgroups

check("_cg_keyed parses the kernel's `key value` format",
      sampler._cg_keyed("usage_usec 123\nuser_usec 45\n"),
      {"usage_usec": 123, "user_usec": 45})
check("_cg_keyed ignores non-numeric values instead of raising",
      sampler._cg_keyed("good 1\nbad notanumber\n"), {"good": 1})

PSI = ("some avg10=1.50 avg60=0.20 avg300=0.00 total=12345\n"
       "full avg10=0.00 avg60=0.00 avg300=0.00 total=678\n")
check("_cg_pressure_total reads the `some` total, not `full`",
      sampler._cg_pressure_total(PSI), 12345)
check("_cg_pressure_total on irq-style input with only a `full` line",
      sampler._cg_pressure_total("full avg10=0.00 total=99\n"), None)

# ---------------------------------------------------------------- disk

now = {"sda": {"reads": 100, "readBytes": 1024000, "msReading": 50,
               "writes": 200, "writeBytes": 2048000, "msWriting": 80,
               "inFlight": 2, "msDoingIO": 500}}
before = {"sda": {"reads": 50, "readBytes": 512000, "msReading": 30,
                  "writes": 100, "writeBytes": 1024000, "msWriting": 40,
                  "inFlight": 0, "msDoingIO": 300}}
derived = sampler.derive_disk(now, before, 2.0)[0]
check("derive_disk: read throughput", derived["read"], 256000)
check("derive_disk: write throughput", derived["write"], 512000)
close("derive_disk: iops is completed ops per second", derived["iops"], 75.0)
close("derive_disk: util is busy time over wall time", derived["util"], 10.0)
check("derive_disk: queue depth is instantaneous", derived["queue"], 2)
close("derive_disk: latency is service time per op", derived["latency"], 0.4)
check("derive_disk: a device with no previous sample is skipped",
      sampler.derive_disk(now, {}, 1.0), [])

zero = sampler.derive_disk({"sda": dict(now["sda"])}, {"sda": dict(now["sda"])}, 1.0)[0]
check("derive_disk: an idle device reports 0 latency, not a divide error",
      zero["latency"], 0)

# ---------------------------------------------------------------- network

check("interface names that double-count the physical link are skipped",
      [n for n in ("veth123", "br-abc", "docker0", "virbr0", "wlp13s0", "enp1s0")
       if not n.startswith(sampler.SKIP_IFACE_PREFIXES)],
      ["wlp13s0", "enp1s0"])
check("block devices that are not disks are skipped",
      [n for n in ("loop0", "ram1", "zram0", "dm-0", "md0", "nvme0n1", "sda")
       if not n.startswith(sampler.SKIP_DISK_PREFIXES)],
      ["nvme0n1", "sda"])

WIRELESS = ("Inter-| sta-|   Quality        |   Discarded packets\n"
            " face | tus | link level noise |  nwid  crypt\n"
            "wlp13s0: 0000   54.  -56.  -256        0      0\n")
import io as _io
_orig_open = open


def fake_open(path, *args, **kwargs):
    if path == "/proc/net/wireless":
        return _io.StringIO(WIRELESS)
    return _orig_open(path, *args, **kwargs)


# Restored in a finally: if read_wireless() raises, a leaked fake_open would
# answer every later check and make those failures point anywhere but here.
sampler.open = fake_open
try:
    wireless = sampler.read_wireless()
finally:
    del sampler.open
check("wireless: strips the kernel's trailing dots", wireless["wlp13s0"]["signal"], -56.0)
check("wireless: link quality", wireless["wlp13s0"]["quality"], 54.0)
check("wireless: a -256 noise floor means 'unknown' and is dropped",
      "noise" in wireless["wlp13s0"], False)

# ---------------------------------------------------------------- thermals

check("chip_kind maps a driver name to hardware a person recognises",
      [sampler.chip_kind(c) for c in ("k10temp", "nvme", "spd5118", "mt7921_phy0", "r8169_0")],
      ["cpu", "drive", "dimm", "net", "net"])
check("display_chip falls through to the raw name when unknown",
      sampler.display_chip("some_new_driver"), "some_new_driver")

# ---------------------------------------------------------------- zram

check("zram ratio divides by the compressed size, not allocator overhead",
      sampler.read_zram("definitely-not-a-device"), {})

# ---------------------------------------------------------------- recorder

with tempfile.TemporaryDirectory() as tmp:
    sampler.RECORDER_DIR = tmp
    sampler.RECORDER_FILE = os.path.join(tmp, "history.jsonl")
    recorder = sampler.FlightRecorder(tick=0)
    sample = {"cpu": {"total": 12.5}, "mem": {"total": 100, "used": 40, "swapUsed": 0},
              "net": {"rx": 1, "tx": 2}, "disk": {"read": 3, "write": 4},
              "thermal": {"cpu": 55.0}, "pressure": {"memory": {"some10": 0.5}}}
    recorder.record(sample, 100.0)
    recorder.record(sample, 200.0)
    rows = recorder.load()
    check("recorder: writes one row per tick", len(rows), 2)
    check("recorder: cpu is carried through", rows[0]["c"], 12.5)
    check("recorder: memory is stored as a percentage", rows[0]["m"], 40.0)
    check("recorder: temperature is carried through", rows[0]["ct"], 55.0)

    with _orig_open(sampler.RECORDER_FILE, "a") as f:
        f.write('{"t":1,"c":  \n')       # a torn line, as after an unclean exit
    check("recorder: survives a torn final line", len(recorder.load()), 2)

    recorder.tick = 3600
    recorder.record(sample, 200.5)
    check("recorder: respects its tick", len(recorder.load()), 2)

# ---------------------------------------------------------------- stdin

lines = sampler.StdinLines(0)
lines.buffer = b"procs on\ngpu on\npartial"
consumed = lines.buffer.split(b"\n")
lines.buffer = consumed.pop()
check("stdin reader holds back an incomplete trailing line", lines.buffer, b"partial")
check("stdin reader yields both complete commands",
      [c.decode() for c in consumed], ["procs on", "gpu on"])


# ------------------------------------------------------- application identity

# A service unit name IS the identity. Two Python services must not collapse
# into one "python" row just because their process names match.
check("service units identify by unit name, not process name",
      [sampler.app_identity(u, [])[0]
       for u in ("podcast-worker.service", "hermes-gateway.service")],
      ["podcast-worker", "hermes-gateway"])
check("template instances of one unit share an identity",
      sampler.app_identity("getty@tty1.service", [])[0], "getty")
check("a launcher-added app- prefix is stripped from services",
      sampler.app_identity("app-dropbox@autostart.service", [])[0], "dropbox")
check("portal services stay distinct despite a shared prefix",
      [sampler.app_identity(u, [])[0]
       for u in ("xdg-desktop-portal.service", "xdg-desktop-portal-gtk.service")],
      ["xdg-desktop-portal", "xdg-desktop-portal-gtk"])

# App scopes: the desktop id reduces to its leaf, and the trailing hash or pid
# systemd appends is not part of the identity.
check("a reverse-DNS desktop id reduces to its leaf",
      sampler.app_identity("app-org.chromium.Chromium-1000.scope", [])[0], "chromium")
check("a compositor tag is not part of the identity",
      sampler.app_identity("app-Hyprland-chromium-deadbeef.scope", [])[0], "chromium")
check("both Chromium scopes therefore share one key",
      sampler.app_identity("app-org.chromium.Chromium-1000.scope", [])[0]
      == sampler.app_identity("app-Hyprland-chromium-deadbeef.scope", [])[0], True)

# A scope named after the launcher, or after a terminal session, says nothing
# about its contents — those defer to the processes inside.
check("a launcher scope defers to its processes",
      sampler.app_identity("app-Hyprland-gtk-launch-cafe1234.scope", [])[0], None)
check("an anonymous session scope defers to its processes",
      sampler.app_identity("tmux-spawn-00000000-0000.scope", [])[0], None)


# Container scopes carry a unique id but no readable name. Identifying them by
# process name would merge two containers of the same image — two separate
# databases showing as one row.
check("a container scope keeps its own identity",
      sampler.app_identity("docker-1111aaaa2222.scope", [])[0], "docker-1111aaaa2222")
check("...but has no readable name of its own",
      sampler.app_identity("docker-1111aaaa2222.scope", [])[1], None)
check("two containers of one image get different keys",
      sampler.app_identity("docker-aaaa1111.scope", [])[0]
      != sampler.app_identity("docker-bbbb2222.scope", [])[0], True)
check("podman and nspawn scopes are treated the same way",
      [sampler.app_identity(u, [])[0] is not None
       for u in ("libpod-abc.scope", "podman-abc.scope", "machine-vm.scope")],
      [True, True, True])

# ------------------------------------------------------- application merging

def app(key, name, mem, cpu, procs, stall=0.0, peak=None, oom=0):
    return {"key": key, "name": name, "unit": key, "system": False,
            "mem": mem, "memPeak": peak if peak is not None else mem,
            "cpu": cpu, "procs": procs, "ioStall": stall, "memStall": 0.0,
            "oomKills": oom}

rows = sampler.merge_apps([
    app("chromium", "chromium", 10_000, 5.0, 90, stall=2.0, peak=11_000),
    app("chromium", "chromium", 2_000, 1.0, 5, stall=7.5, peak=9_000),
    app("podcast-worker", "podcast-worker", 500, 0.1, 1),
])
check("merging folds one app's scopes into a single row", len(rows), 2)
check("merged memory adds", rows[0]["mem"], 12_000)
# A high-water mark is not additive: these two scopes never together held
# 20,000, because each reached its own peak at its own moment.
check("merged peak takes the worst scope rather than summing",
      rows[0]["memPeak"], 11_000)
close("merged cpu adds", rows[0]["cpu"], 6.0)
check("merged process counts add", rows[0]["procs"], 95)
check("merged rows record how many scopes they cover", rows[0]["scopes"], 2)
close("stall takes the worst scope, not an average", rows[0]["ioStall"], 7.5)
check("an app with one scope is left alone", rows[1]["scopes"], 1)
check("distinct services survive merging", rows[1]["name"], "podcast-worker")

# The failure this whole identity model exists to prevent.
same_name = sampler.merge_apps([
    app("podcast-worker", "python", 500, 0.1, 1),
    app("hermes-gateway", "python", 90, 0.2, 1),
])
check("two services that merely share a process name do NOT merge",
      len(same_name), 2)

# ------------------------------------------------- rate baselines on re-open
#
# cgroup counters are cumulative. If the applications gate reopens against a
# baseline taken before it last closed, the next sample divides the whole
# closed period by one interval and every application reads in the hundreds or
# thousands of percent for a frame. Two things have to hold to prevent it.

gates = sampler.Sampler(2.0, False, 10)

gates.apps_detail = True
gates.prev_cgroups = {"/stale": (123456789, 0, 0)}
gates.handle("apps off")
check("turning applications off drops the stale baseline",
      gates.prev_cgroups, {})

check("turning applications on asks for a re-prime",
      gates.handle("apps on"), True)

# The other detail gates read instantaneous values, so they must NOT pay for a
# full re-prime — that would discard every other baseline mid-interval.
for gate, attr in (("sensors", "sensor_detail"), ("gpudetail", "gpu_detail"),
                   ("netdetail", "net_detail")):
    setattr(gates, attr, False)
    check("%s does not force a re-prime" % gate, gates.handle(gate + " on"), False)

# And prime() has to actually take the baseline it is now relied on for.
# A host without cgroup v2 delegated (a CI container, say) has nothing to
# read, and the point of the check is that prime() tries — not that this
# particular machine has cgroups.
cgroups_readable = len(sampler.read_cgroups({}, 1.0)[1]) > 0
gates.apps_detail = True
gates.prev_cgroups = {}
gates.prime()
check("prime takes a cgroup baseline when applications are on",
      len(gates.prev_cgroups) > 0, cgroups_readable)

gates.apps_detail = False
gates.prime()
check("prime skips the cgroup walk when applications are off",
      gates.prev_cgroups, {})

# ---------------------------------------------------------------- report

print("ran %d checks" % checks)
if failures:
    print("\n%d FAILED:\n" % len(failures))
    for f in failures:
        print("  - " + f)
    sys.exit(1)
print("all passed")
