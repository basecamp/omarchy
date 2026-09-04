#!/usr/bin/env python3
"""Stream system and process telemetry as JSON lines for the Omarchy task manager.

One JSON object per line on stdout, one per sample interval. Everything comes
from /proc, and the previous snapshot is held in memory so CPU figures are true
deltas over the interval rather than the since-boot averages `ps` reports.

Commands on stdin, one per line:

  procs on | off      include or omit the process table
  threads <pid>|off   include per-thread CPU for one process
  gpudetail on | off  include PCIe throughput and per-client VRAM
  sensors on | off    include the off-CPU hwmon sensors (NVMe, DIMM, wifi)
  netdetail on | off  include NIC error counters and the socket table
  diskdetail on | off include per-process block I/O
  apps on | off       include per-application cgroup accounting
  groupapps on | off  fold multiple scopes of one app into a single row
  gpu on | off        map the GPU driver (off by default; costs ~31MB RSS)
  sockets on | off    include per-process socket counts
  openfiles <pid>|off list one process's open files and sockets
  history             replay the recorded history as one JSON line
  interval <secs>     change the sample rate
  limit <n>           how many processes to emit (sorted by CPU)
  quit                exit

Everything optional is off by default and switched on by whichever surface
needs it, because the optional readings are the expensive ones: the process
table is three /proc reads per pid, and NVML's PCIe counters block for ~20ms
each. A bar sparkline only needs the cheap aggregate lines, and pays for
nothing else.
"""

import ctypes
import glob
import subprocess
import json
import os
import pwd
import re
import select
import sys
import time

PAGE_SIZE = os.sysconf("SC_PAGE_SIZE")
SECTOR_BYTES = 512

# Software threads of one expanded process (/proc/<pid>/task/*), NOT CPU
# hardware threads — those come from /proc/stat's cpuN lines and are never
# capped, so a 256-thread Threadripper reports 256 cores. This is only a
# backstop against a pathological process turning one sample into megabytes of
# JSON; a JVM or browser in the low thousands still lists in full.
THREAD_LIMIT = 2000

# How many VRAM-holding clients NVML is asked about per device.
GPU_PROCESS_LIMIT = 64

# How often to fork systemctl for failed-unit status. Units fail rarely and the
# fork is the most expensive single thing this sampler can do.
FAILED_UNIT_POLL_SEC = 30

# Interfaces and block devices that would only add noise to a machine-wide
# throughput readout: loopback is local traffic, container/bridge/virtual links
# double-count the physical interface underneath them, and loop/ram/zram
# devices are not disks anyone is trying to see the I/O of. Device-mapper
# nodes (LUKS, LVM) are skipped for the same reason as bridges — their traffic
# lands on the physical device below and is already counted there.
SKIP_IFACE_PREFIXES = ("veth", "docker", "br-", "virbr", "vnet", "tap")
SKIP_DISK_PREFIXES = ("loop", "ram", "zram", "dm-", "md")

_uid_names = {}


def username(uid):
    name = _uid_names.get(uid)
    if name is None:
        try:
            name = pwd.getpwuid(uid).pw_name
        except KeyError:
            name = str(uid)
        _uid_names[uid] = name
    return name


def read_cpu():
    """[(busy, total)] jiffie counters: index 0 is the aggregate, 1.. are cores."""
    out = []
    with open("/proc/stat") as f:
        for line in f:
            if not line.startswith("cpu"):
                break
            values = [int(v) for v in line.split()[1:]]
            # idle + iowait both count as "not doing work" the way top does it.
            idle = values[3] + (values[4] if len(values) > 4 else 0)
            out.append((sum(values) - idle, sum(values)))
    return out


MEMINFO_FIELDS = (
    "MemTotal", "MemFree", "MemAvailable", "Buffers", "Cached",
    "SReclaimable", "SUnreclaim", "Slab", "SwapTotal", "SwapFree",
    "AnonPages", "Mapped", "Shmem", "KernelStack", "PageTables",
    "Dirty", "Writeback", "Committed_AS", "CommitLimit",
    "Active(file)", "Inactive(file)", "Active(anon)", "Inactive(anon)",
)


def read_mem():
    """Composition as well as totals — one parse of a file we read anyway.

    "22 GB used" hides that several of those gigabytes are kernel slab rather
    than anything a process allocated, so the breakdown comes along for free
    with the summary.
    """
    wanted = set(MEMINFO_FIELDS)
    raw = {}
    with open("/proc/meminfo") as f:
        for line in f:
            key, _, rest = line.partition(":")
            if key in wanted:
                raw[key] = int(rest.split()[0]) * 1024

    total = raw.get("MemTotal", 0)
    # MemAvailable is the kernel's own estimate of what a new allocation could
    # get, which is what "used" should be measured against — subtracting only
    # MemFree would count reclaimable page cache as used.
    available = raw.get("MemAvailable", raw.get("MemFree", 0))
    swap_total = raw.get("SwapTotal", 0)
    return {
        "total": total,
        "used": total - available,
        "avail": available,
        "free": raw.get("MemFree", 0),
        "cached": raw.get("Cached", 0) + raw.get("SReclaimable", 0),
        "buffers": raw.get("Buffers", 0),
        "swapTotal": swap_total,
        "swapUsed": swap_total - raw.get("SwapFree", 0),
        # Composition. `anon` is what processes actually hold; `slab` is the
        # kernel's own allocator, split into the part it can hand back under
        # pressure and the part it cannot.
        "anon": raw.get("AnonPages", 0),
        "mapped": raw.get("Mapped", 0),
        "shmem": raw.get("Shmem", 0),
        "slab": raw.get("Slab", 0),
        "slabReclaimable": raw.get("SReclaimable", 0),
        "slabUnreclaimable": raw.get("SUnreclaim", 0),
        "kernelStack": raw.get("KernelStack", 0),
        "pageTables": raw.get("PageTables", 0),
        "dirty": raw.get("Dirty", 0),
        "writeback": raw.get("Writeback", 0),
        "committed": raw.get("Committed_AS", 0),
        "commitLimit": raw.get("CommitLimit", 0),
        "activeFile": raw.get("Active(file)", 0),
        "inactiveFile": raw.get("Inactive(file)", 0),
    }


def read_pressure():
    """PSI stall percentages — the honest "is this machine struggling" signal.

    A memory bar at 90% may be perfectly healthy page cache; `some avg10` above
    zero means tasks actually stalled waiting for memory. That is the number
    worth alarming on, so it is collected for all three resources.
    """
    out = {}
    for resource in ("cpu", "memory", "io"):
        try:
            with open("/proc/pressure/" + resource) as f:
                text = f.read()
        except OSError:
            continue  # kernel built without PSI, or cgroup restrictions
        entry = {}
        for line in text.splitlines():
            parts = line.split()
            if not parts:
                continue
            scope = parts[0]  # "some" or "full"
            for field in parts[1:]:
                key, _, value = field.partition("=")
                if key.startswith("avg"):
                    try:
                        entry[scope + key[3:]] = float(value)
                    except ValueError:
                        pass
        if entry:
            out[resource] = entry
    return out


def read_swaps():
    """Every swap area, with zram compression folded in where it applies."""
    out = []
    try:
        with open("/proc/swaps") as f:
            lines = f.readlines()[1:]
    except OSError:
        return out

    for line in lines:
        fields = line.split()
        if len(fields) < 5:
            continue
        name = fields[0]
        entry = {
            "name": name,
            "type": fields[1],
            # /proc/swaps counts in kibibytes regardless of page size.
            "size": int(fields[2]) * 1024,
            "used": int(fields[3]) * 1024,
            "priority": int(fields[4]),
        }

        device = os.path.basename(name)
        if device.startswith("zram"):
            entry.update(read_zram(device))
        out.append(entry)
    return out


def read_zram(device):
    """Compression figures for one zram device.

    mm_stat is a single line: orig_data_size compr_data_size mem_used_total
    mem_limit mem_used_max same_pages pages_compacted huge_pages.
    """
    try:
        with open("/sys/block/%s/mm_stat" % device) as f:
            fields = [int(v) for v in f.read().split()]
    except (OSError, ValueError):
        return {}
    if len(fields) < 3:
        return {}

    original, compressed, used_total = fields[0], fields[1], fields[2]
    out = {
        "zramOriginal": original,
        "zramCompressed": compressed,
        "zramUsed": used_total,
        # What the compression actually bought: the pages' uncompressed size
        # minus the RAM zram is really holding, allocator overhead included.
        "zramSaved": max(0, original - used_total),
        # Ratio is compression, so it divides by the compressed size — dividing
        # by mem_used_total would fold in allocator overhead and report a
        # nonsensical sub-1x "ratio" on an idle device holding a single page.
        "zramRatio": round(original / compressed, 2) if compressed > 0 else 0,
    }
    try:
        with open("/sys/block/%s/comp_algorithm" % device) as f:
            text = f.read()
        # The active algorithm is the bracketed one in the list.
        for token in text.split():
            if token.startswith("["):
                out["zramAlgorithm"] = token.strip("[]")
                break
    except OSError:
        pass
    return out


def read_sysfs_net(iface, name):
    try:
        with open("/sys/class/net/%s/%s" % (iface, name)) as f:
            return f.read().strip()
    except OSError:
        return None


def interface_is_live(iface):
    """Whether a link is actually carrying traffic.

    An unplugged NIC still appears in /proc/net/dev with its counters frozen at
    zero, and listing it as an active interface is a small lie. TUN devices like
    tailscale0 report operstate "unknown" forever, so carrier is the signal that
    works for both.
    """
    if read_sysfs_net(iface, "carrier") == "1":
        return True
    return read_sysfs_net(iface, "operstate") == "up"


def read_net():
    """{iface: (rx_bytes, tx_bytes)} cumulative counters, live links only."""
    out = {}
    with open("/proc/net/dev") as f:
        lines = f.readlines()[2:]
    for line in lines:
        name, _, rest = line.partition(":")
        name = name.strip()
        if name == "lo" or name.startswith(SKIP_IFACE_PREFIXES):
            continue
        fields = rest.split()
        if len(fields) < 9:
            continue
        if not interface_is_live(name):
            continue
        out[name] = (int(fields[0]), int(fields[8]))
    return out


NET_ERROR_COUNTERS = ("rx_errors", "tx_errors", "rx_dropped", "tx_dropped")


def read_links(ifaces, detailed=False):
    """Per-interface link state, and on request its error counters.

    Link state is cheap enough to read every sample; the error counters are
    another six file reads per interface and only appear in the expanded view.
    """
    wireless = read_wireless()
    out = []
    for iface in sorted(ifaces):
        speed = read_sysfs_net(iface, "speed")
        # Parsed once, then judged: -1 is the kernel's "not applicable" (wifi,
        # tunnels) and 0 is "not negotiated". Both mean there is no speed to show.
        link_speed = int(speed) if speed and speed.lstrip("-").isdigit() else None
        if link_speed is not None and link_speed <= 0:
            link_speed = None
        entry = {
            "name": iface,
            "state": read_sysfs_net(iface, "operstate") or "unknown",
            "carrier": read_sysfs_net(iface, "carrier") == "1",
            "mtu": int(read_sysfs_net(iface, "mtu") or 0),
            "duplex": read_sysfs_net(iface, "duplex"),
            "speed": link_speed,
        }
        if iface in wireless:
            entry["wireless"] = wireless[iface]
        if detailed:
            for counter in NET_ERROR_COUNTERS:
                value = read_sysfs_net(iface, "statistics/" + counter)
                entry[counter] = int(value) if value and value.isdigit() else 0
        out.append(entry)
    return out


def read_wireless():
    """{iface: {quality, signal}} from /proc/net/wireless.

    Values carry a trailing '.' in the kernel's fixed-width formatting. `noise`
    is reported as -256 when the driver has nothing, so it is dropped rather
    than shown as a real floor.
    """
    out = {}
    try:
        with open("/proc/net/wireless") as f:
            lines = f.readlines()[2:]
    except OSError:
        return out

    for line in lines:
        name, _, rest = line.partition(":")
        fields = rest.split()
        if len(fields) < 4:
            continue
        try:
            quality = float(fields[1].rstrip("."))
            signal = float(fields[2].rstrip("."))
        except ValueError:
            continue
        entry = {"quality": quality, "signal": signal}
        try:
            noise = float(fields[3].rstrip("."))
            if noise > -256:
                entry["noise"] = noise
        except ValueError:
            pass
        out[name.strip()] = entry
    return out


# /proc/net/tcp state codes worth naming; the rest are transient handshake
# states that would only add noise to a summary.
TCP_STATES = {"01": "established", "06": "timeWait", "08": "closeWait", "0A": "listen"}


def read_sockets():
    """Counts of TCP sockets by state, v4 and v6 together."""
    counts = {}
    total = 0
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 4:
                continue
            total += 1
            name = TCP_STATES.get(fields[3])
            if name:
                counts[name] = counts.get(name, 0) + 1
    counts["total"] = total
    return counts


def read_disk():
    """{device: (read_bytes, written_bytes)} cumulative counters, whole disks only."""
    out = {}
    for name, fields in iter_diskstats():
        out[name] = (int(fields[5]) * SECTOR_BYTES, int(fields[9]) * SECTOR_BYTES)
    return out


def iter_diskstats():
    """(name, fields) for every whole block device worth reporting."""
    with open("/proc/diskstats") as f:
        for line in f:
            fields = line.split()
            if len(fields) < 14:
                continue
            name = fields[2]
            if name.startswith(SKIP_DISK_PREFIXES):
                continue
            # Partitions have a parent in /sys/block; only whole devices appear
            # there directly, which keeps sda1 from double-counting sda.
            if not os.path.exists("/sys/block/" + name):
                continue
            yield name, fields


def read_disk_stats():
    """Raw counters per device for the iostat-style derived figures.

    Field order after major/minor/name: reads, reads merged, sectors read, ms
    reading, writes, writes merged, sectors written, ms writing, I/Os in
    flight, ms doing I/O, weighted ms doing I/O.
    """
    out = {}
    for name, fields in iter_diskstats():
        out[name] = {
            "reads": int(fields[3]),
            "readBytes": int(fields[5]) * SECTOR_BYTES,
            "msReading": int(fields[6]),
            "writes": int(fields[7]),
            "writeBytes": int(fields[9]) * SECTOR_BYTES,
            "msWriting": int(fields[10]),
            "inFlight": int(fields[11]),
            "msDoingIO": int(fields[12]),
        }
    return out


def derive_disk(current, previous, elapsed):
    """Throughput, IOPS, utilisation, queue depth and latency per device.

    Utilisation is the share of wall-clock the device spent with any request
    outstanding — iostat's %util. On an NVMe drive that serves many requests in
    parallel it saturates long before the device does, so it reads as "busy",
    not "full".
    """
    out = []
    for name in sorted(current):
        now = current[name]
        before = previous.get(name)
        if before is None:
            continue

        reads = max(0, now["reads"] - before["reads"])
        writes = max(0, now["writes"] - before["writes"])
        operations = reads + writes
        busy_ms = max(0, now["msDoingIO"] - before["msDoingIO"])
        service_ms = max(0, (now["msReading"] - before["msReading"])
                         + (now["msWriting"] - before["msWriting"]))

        out.append({
            "name": name,
            "read": round(max(0, now["readBytes"] - before["readBytes"]) / elapsed),
            "write": round(max(0, now["writeBytes"] - before["writeBytes"]) / elapsed),
            "iops": round(operations / elapsed, 1),
            "util": round(min(100.0, busy_ms / (elapsed * 1000.0) * 100.0), 1),
            "queue": now["inFlight"],
            # Mean time a request spent in the driver, over the interval. Only
            # meaningful when something actually happened.
            "latency": round(service_ms / operations, 2) if operations > 0 else 0,
        })
    return out


def read_filesystems():
    """Usage per real filesystem, one entry per device rather than per mount.

    A btrfs pool with subvolumes at /, /home and /var/log is one filesystem
    reported four times by /proc/mounts; listing it four times would imply four
    separate things to run out of.
    """
    seen = {}
    order = []
    try:
        with open("/proc/mounts") as f:
            lines = f.readlines()
    except OSError:
        return []

    for line in lines:
        fields = line.split()
        if len(fields) < 3:
            continue
        device, mount, fstype = fields[0], fields[1], fields[2]
        if not device.startswith("/dev/"):
            continue
        try:
            stats = os.statvfs(mount)
        except OSError:
            continue
        total = stats.f_blocks * stats.f_frsize
        if total <= 0:
            continue
        # Available-to-unprivileged, matching what df reports as the usable
        # figure — f_bfree includes root's reserve, which nothing can spend.
        available = stats.f_bavail * stats.f_frsize
        used = total - stats.f_bfree * stats.f_frsize

        if device in seen:
            seen[device]["mounts"].append(mount)
            continue
        seen[device] = {
            "device": device,
            "mounts": [mount],
            "fstype": fstype,
            "total": total,
            "used": used,
            "avail": available,
            # df's Use%: measured against what is actually spendable, so the
            # root reserve on an ext4 volume does not read as usable free
            # space. This is the number to compare against `df`.
            "percent": round(used / (used + available) * 100, 1) if (used + available) > 0 else 0,
        }
        order.append(device)

    return [seen[d] for d in order]


def read_socket_inodes():
    """{inode: (proto, state, local, remote)} for every TCP and UDP socket.

    The kernel does not record which process owns a socket, so the standard
    join is inode -> /proc/<pid>/fd. Every tool that does per-process network
    on Linux — nethogs, procs, psutil — uses exactly this, and inherits the
    same ceiling: you see your own processes' sockets, not other users'.
    """
    TCP_STATES = {"01": "ESTABLISHED", "02": "SYN_SENT", "06": "TIME_WAIT", "0A": "LISTEN"}

    def parse_addr(raw):
        host, _, port = raw.partition(":")
        try:
            port = int(port, 16)
        except ValueError:
            return raw
        if len(host) == 8:                      # IPv4, little-endian hex
            octets = [int(host[i:i + 2], 16) for i in (6, 4, 2, 0)]
            return "%d.%d.%d.%d:%d" % (*octets, port)
        return "[v6]:%d" % port

    out = {}
    for path, proto in (("/proc/net/tcp", "tcp"), ("/proc/net/tcp6", "tcp6"),
                        ("/proc/net/udp", "udp"), ("/proc/net/udp6", "udp6")):
        try:
            with open(path) as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10:
                continue
            out[fields[9]] = (
                proto,
                TCP_STATES.get(fields[3], fields[3]) if proto.startswith("tcp") else "",
                parse_addr(fields[1]),
                parse_addr(fields[2]),
            )
    return out


def read_open_files(pid):
    """Files, sockets and pipes held by one process.

    Answers "what is holding this port" and "why can't I unmount that" — the
    two questions that otherwise send people to lsof. On demand only: a browser
    can hold nine hundred descriptors.
    """
    sockets_by_inode = None
    files, sockets, pipes = [], [], 0
    try:
        entries = list(os.scandir("/proc/%d/fd" % pid))
    except OSError:
        return None                              # not ours, or already gone

    for entry in entries:
        try:
            target = os.readlink(entry.path)
        except OSError:
            continue
        if target.startswith("socket:["):
            if sockets_by_inode is None:
                sockets_by_inode = read_socket_inodes()
            info = sockets_by_inode.get(target[8:-1])
            if info:
                sockets.append({"proto": info[0], "state": info[1],
                                "local": info[2], "remote": info[3]})
            else:
                sockets.append({"proto": "unix", "state": "", "local": "", "remote": ""})
        elif target.startswith(("pipe:", "anon_inode:")):
            pipes += 1
        elif target.startswith("/"):
            files.append(target)

    files.sort()
    return {
        "pid": pid,
        "total": len(entries),
        "files": files[:200],
        "sockets": sockets[:200],
        "pipes": pipes,
    }


def count_process_sockets(pids):
    """{pid: (listening, established)} — cheap enough for the whole table.

    Counts only; the addresses come from read_open_files when a row is opened.
    """
    sockets_by_inode = read_socket_inodes()
    out = {}
    for pid in pids:
        listening = established = 0
        try:
            for entry in os.scandir("/proc/%d/fd" % pid):
                try:
                    target = os.readlink(entry.path)
                except OSError:
                    continue
                if not target.startswith("socket:["):
                    continue
                info = sockets_by_inode.get(target[8:-1])
                if not info:
                    continue
                if info[1] == "LISTEN":
                    listening += 1
                elif info[1] == "ESTABLISHED":
                    established += 1
        except OSError:
            continue
        if listening or established:
            out[pid] = (listening, established)
    return out


def read_process_io(pids):
    """{pid: (read_bytes, write_bytes)} of real block I/O, where permitted.

    /proc/<pid>/io is readable only for processes the caller owns, so on a
    normal session this covers your own processes and silently omits root's.
    The count of what was readable is reported so the UI can say so.
    """
    out = {}
    for pid in pids:
        try:
            with open("/proc/%d/io" % pid) as f:
                text = f.read()
        except OSError:
            continue  # not ours, or exited
        read_bytes = write_bytes = 0
        for line in text.splitlines():
            key, _, value = line.partition(":")
            if key == "read_bytes":
                read_bytes = int(value)
            elif key == "write_bytes":
                write_bytes = int(value)
        out[pid] = (read_bytes, write_bytes)
    return out


# ---------------------------------------------------------- flight recorder
#
# Every history ring in the UI lives in the shell process, so an `omarchy
# update` — which restarts the shell — erases all of it. That reduces the tool
# to answering "what is happening now", never "what happened while I was
# asleep". A small append-only log on disk fixes that.
#
# This is fixed-tick sampling, the same model zenith uses. It is deliberately
# not atop's model: atop hooks BSD process accounting and can therefore
# attribute a process that both started and exited between two samples.
# Nothing here can see such a process, and the recorder does not pretend to.

RECORDER_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "omarchy", "omatask")
RECORDER_FILE = os.path.join(RECORDER_DIR, "history.jsonl")
# One week at a 30s tick is ~20k rows, comfortably under 4MB.
RECORDER_TICK_SEC = 30
RECORDER_MAX_ROWS = 20160


class FlightRecorder:
    """Appends one downsampled row per tick, and prunes when it reads back.

    Keys are single letters on purpose: this file is appended to forever, and
    spelled-out names would be most of its bytes.
    """

    def __init__(self, tick=RECORDER_TICK_SEC):
        self.tick = tick
        self.last_write = 0.0
        self.enabled = True
        try:
            os.makedirs(RECORDER_DIR, exist_ok=True)
        except OSError:
            self.enabled = False

    def load(self, limit=RECORDER_MAX_ROWS):
        """Recorded rows, oldest first. Prunes the file only when overlong."""
        if not self.enabled:
            return []
        try:
            with open(RECORDER_FILE) as f:
                lines = f.readlines()
        except OSError:
            return []

        rows = []
        for line in lines[-limit:]:
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue          # a torn final line after an unclean exit
        if len(lines) > limit * 1.25:
            try:
                with open(RECORDER_FILE, "w") as f:
                    for row in rows:
                        f.write(json.dumps(row, separators=(",", ":")) + "\n")
            except OSError:
                pass
        return rows

    def record(self, sample, now):
        if not self.enabled or now - self.last_write < self.tick:
            return
        self.last_write = now

        cpu = sample.get("cpu") or {}
        mem = sample.get("mem") or {}
        net = sample.get("net") or {}
        disk = sample.get("disk") or {}
        thermal = sample.get("thermal") or {}
        devices = (sample.get("gpu") or {}).get("devices") or [{}]
        pressure = (sample.get("pressure") or {}).get("memory") or {}
        total = mem.get("total") or 1

        row = {
            "t": int(time.time()),
            "c": round(cpu.get("total", 0), 1),
            "m": round(mem.get("used", 0) / total * 100, 1),
            "s": round(mem.get("swapUsed", 0) / 1e6),
            "nr": net.get("rx", 0),
            "nt": net.get("tx", 0),
            "dr": disk.get("read", 0),
            "dw": disk.get("write", 0),
            "g": devices[0].get("util"),
            "ct": thermal.get("cpu"),
            "gt": devices[0].get("temp"),
            "p": round(pressure.get("some10", 0), 2),
        }
        try:
            with open(RECORDER_FILE, "a") as f:
                f.write(json.dumps(row, separators=(",", ":")) + "\n")
        except OSError:
            self.enabled = False


# ---------------------------------------------------------------- hardware
#
# Readings that no generic monitor surfaces, all unprivileged, all from files
# the kernel already maintains.


def read_cpufreq():
    """Per-core delivered frequency, plus the policy that governs it.

    `cpuinfo_avg_freq` is amd-pstate's APERF/MPERF-derived *actual* average —
    what the core really ran at. `scaling_cur_freq` is the requested operating
    point, which lags under this driver rather than being wrong. Prefer the
    former where it exists and fall back where it does not.
    """
    freqs = []
    index = 0
    while True:
        base = "/sys/devices/system/cpu/cpu%d/cpufreq" % index
        if not os.path.isdir(base):
            break
        value = _cg_int(os.path.join(base, "cpuinfo_avg_freq"))
        if value is None:
            value = _cg_int(os.path.join(base, "scaling_cur_freq"))
        freqs.append(round((value or 0) / 1000.0))   # kHz -> MHz
        index += 1

    if not freqs:
        return {}

    policy = "/sys/devices/system/cpu/cpu0/cpufreq"
    out = {
        "cores": freqs,
        "min": round((_cg_int(policy + "/scaling_min_freq") or 0) / 1000.0),
        "max": round((_cg_int(policy + "/cpuinfo_max_freq") or 0) / 1000.0),
        "governor": (_cg_read(policy + "/scaling_governor") or "").strip() or None,
        "driver": (_cg_read(policy + "/scaling_driver") or "").strip() or None,
    }
    boost = _cg_read("/sys/devices/system/cpu/cpufreq/boost")
    if boost is not None:
        out["boost"] = boost.strip() == "1"
    return out


def read_interrupts():
    """Softirq distribution across cores, to catch a pinned interrupt load.

    /proc/interrupts is the richer file but costs ~240us to read — the most
    expensive in /proc — because it is O(irqs x cpus). /proc/softirqs is a
    tenth of that and carries the line that actually matters on a desktop:
    NET_RX, which lands entirely on one core when a NIC's affinity is wrong.
    """
    out = {}
    try:
        with open("/proc/softirqs") as f:
            lines = f.readlines()[1:]
    except OSError:
        return out

    for line in lines:
        name, _, rest = line.partition(":")
        name = name.strip()
        if name not in ("NET_RX", "NET_TX", "BLOCK", "TIMER", "SCHED"):
            continue
        try:
            counts = [int(v) for v in rest.split()]
        except ValueError:
            continue
        if not counts:
            continue
        busiest = max(counts)
        quietest = min(counts)
        out[name] = {
            "counts": counts,
            "busiestCore": counts.index(busiest),
            # A ratio, not a difference: on an idle core the absolute numbers
            # are meaningless but a 300x skew is a misconfiguration.
            "imbalance": round(busiest / quietest, 1) if quietest > 0 else None,
        }
    return out


def read_btrfs():
    """Commit stalls, allocation headroom and device errors.

    Three things `df` cannot tell you: that a commit blocked the filesystem for
    two seconds, that metadata is nearly full while data looks fine (which is
    how btrfs actually runs out of space), and that a device has logged errors.
    """
    out = []
    for fsdir in sorted(glob.glob("/sys/fs/btrfs/*")):
        stats = _cg_keyed(_cg_read(os.path.join(fsdir, "commit_stats")))
        if not stats:
            continue
        entry = {
            "label": (_cg_read(os.path.join(fsdir, "label")) or "").strip() or os.path.basename(fsdir)[:8],
            "commits": stats.get("commits", 0),
            "lastCommitMs": stats.get("last_commit_ms", 0),
            "maxCommitMs": stats.get("max_commit_ms", 0),
            "allocation": {},
            "errors": 0,
        }
        for kind in ("data", "metadata", "system"):
            total = _cg_int(os.path.join(fsdir, "allocation", kind, "total_bytes"))
            used = _cg_int(os.path.join(fsdir, "allocation", kind, "bytes_used"))
            if total:
                entry["allocation"][kind] = {
                    "total": total, "used": used or 0,
                    "percent": round((used or 0) / total * 100, 1),
                }
        for devdir in glob.glob(os.path.join(fsdir, "devinfo", "*")):
            errors = _cg_keyed(_cg_read(os.path.join(devdir, "error_stats")))
            entry["errors"] += sum(errors.values())
        out.append(entry)
    return out


def read_failed_units():
    """systemd units in a failed state, system and user.

    There is no file to read this from: failure is derived state, so the answer
    has to come from systemd itself. Forking `systemctl` twice costs several
    milliseconds — more than everything else in a sample combined — which is why
    the caller polls this on its own slow timer and carries the last answer
    between polls rather than asking every tick.
    """
    failed = []
    for scope, command in (("system", ["systemctl", "--failed", "--no-legend", "--plain"]),
                           ("user", ["systemctl", "--user", "--failed", "--no-legend", "--plain"])):
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=4)
        except (OSError, subprocess.SubprocessError):
            continue
        for line in result.stdout.splitlines():
            parts = line.split()
            if parts and parts[0].endswith((".service", ".timer", ".mount", ".socket")):
                failed.append({"unit": parts[0], "scope": scope})
    return failed


# ------------------------------------------------------------- cgroups v2
#
# Omarchy Quattro launches every application into its own systemd scope, which
# means the kernel is already grouping processes the way a person thinks about
# them. Reading those groups gives true per-application accounting — one
# "Chromium" row instead of forty-seven chromium processes — and `memory.current`
# is the honest figure, without the shared-page double counting that makes a
# sum of RSS meaningless.

CGROUP_ROOT = "/sys/fs/cgroup"

# Where user applications and system services live. Both are world-readable.
CGROUP_SCAN_ROOTS = (
    "user.slice/user-%d.slice/user@%d.service" % (os.getuid(), os.getuid()),
    "system.slice",
)

def _cg_read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def _cg_int(path):
    text = _cg_read(path)
    try:
        return int(text.strip())
    except (AttributeError, ValueError):
        return None


def _cg_keyed(text):
    """Parse the `key value` format used by cpu.stat, memory.stat, memory.events."""
    out = {}
    for line in (text or "").splitlines():
        parts = line.split()
        if len(parts) >= 2:
            try:
                out[parts[0]] = int(parts[1])
            except ValueError:
                pass
    return out


def _cg_pressure_total(text):
    """Microseconds of `some` stall, cumulative.

    PSI is exposed per cgroup even when the matching controller is not
    delegated — which is why io *stall* can be attributed per application on a
    system where io *bytes* cannot.
    """
    for line in (text or "").splitlines():
        if not line.startswith("some"):
            continue
        for field in line.split():
            if field.startswith("total="):
                try:
                    return int(field.split("=", 1)[1])
                except ValueError:
                    return None
    return None


# Deriving an application's identity is the hard part of grouping by cgroup,
# and getting it wrong is worse than not grouping at all.
#
# Two failure modes pull in opposite directions:
#
#   * The same app can own several scopes. Chromium launched from the Omarchy
#     menu and Chromium activated through XDG land in different scopes and
#     should read as one application.
#   * Different apps can share a process name. `podcast-worker.service` and
#     `hermes-gateway.service` are both `python`; collapsing them because their
#     comm matches would merge two unrelated programs into a meaningless row.
#
# So identity comes from the *unit*, which systemd already made unique, and
# only falls back to the process name where the unit name carries nothing —
# an anonymous `tmux-spawn-<uuid>.scope` says nothing about what is inside it.

# systemd escapes characters it cannot put in a unit name.
UNIT_UNESCAPE = (("\\x2d", "-"), ("\\x40", "@"), ("\\x5f", "_"))

# `app-<launcher>-<something>-<hash>.scope`. The launcher is not the app —
# `app-Hyprland-gtk-launch-<hash>.scope` contains Slack — so a scope whose
# middle section is a known launcher has to be identified from its processes.
LAUNCHERS = ("gtk-launch", "uwsm-app", "systemd-run", "flatpak", "sh", "bash", "env")

# Scopes whose name is a session identifier rather than an application.
ANONYMOUS_SCOPE_PREFIXES = ("tmux-spawn-", "session-", "vte-spawn-")

# Container runtimes name a scope after the container instance. Two containers
# from the same image run the same binary, so identifying them by process name
# would merge two separate databases into one row — the container id is the
# identity, even though it is unreadable and the name has to come from inside.
CONTAINER_SCOPE_PREFIXES = ("docker-", "libpod-", "podman-", "crio-", "machine-")


def _unescape_unit(name):
    for escaped, plain in UNIT_UNESCAPE:
        name = name.replace(escaped, plain)
    return name


def app_identity(dirname, pids):
    """(key, display) for one cgroup.

    `key` is what rows are merged on; `display` is what a person reads.
    """
    name = _unescape_unit(dirname)

    if name.endswith(".service"):
        # A service unit name is already a unique, human-meaningful identity.
        # This is what keeps podcast-worker and hermes-gateway apart.
        stem = name[:-len(".service")]
        stem = stem.split("@", 1)[0]          # template instances share an app
        if stem.startswith("app-"):
            stem = stem[len("app-"):]
        return stem, stem

    if name.endswith(".scope"):
        stem = name[:-len(".scope")]

        if stem.startswith(CONTAINER_SCOPE_PREFIXES):
            # Unique key, but no readable name: the container's name lives in
            # the runtime's daemon, not anywhere on this side of the API. The
            # caller labels it from its processes and appends a short id so two
            # containers of the same image stay tellable apart.
            return stem, None

        if stem.startswith(ANONYMOUS_SCOPE_PREFIXES):
            # A terminal pane. What matters is the program running in it.
            return None, None

        if stem.startswith("app-"):
            parts = stem[len("app-"):].split("-")
            # Drop the trailing hash or pid systemd appends.
            if len(parts) > 1 and re.fullmatch(r"[0-9a-f]{6,}|\d+", parts[-1]):
                parts = parts[:-1]
            # Drop a leading desktop/compositor tag.
            if parts and parts[0] in ("Hyprland", "gnome", "KDE", "uwsm"):
                parts = parts[1:]
            candidate = "-".join(parts)
            if candidate and not candidate.startswith(LAUNCHERS):
                # A reverse-DNS desktop id reduces to its last component:
                # org.chromium.Chromium -> chromium.
                leaf = candidate.split(".")[-1] if "." in candidate else candidate
                return leaf.lower(), leaf.lower()

    return None, None


# Resolving a scope's name from its processes means reading two files per
# candidate, which dominates a cgroup sweep. Names change only when membership
# does, so cache on the leading pid and re-resolve when that moves.
_scope_names = {}


def scope_display_name(dirname, pids):
    """The heaviest member's name, for scopes whose own name says nothing.

    Heaviest rather than first: a scope's first pid is often a launcher or a
    crash handler that outlives its purpose — Chromium's is `chrome_crashpad`.
    """
    cache_key = (dirname, pids[0] if pids else "")
    cached = _scope_names.get(cache_key)
    if cached is not None:
        return cached

    best = None
    best_rss = -1
    for pid in pids[:24]:
        try:
            with open("/proc/%s/statm" % pid) as f:
                rss = int(f.read().split()[1]) * PAGE_SIZE
            with open("/proc/%s/comm" % pid) as f:
                comm = f.read().strip()
        except (OSError, ValueError, IndexError):
            continue
        if rss > best_rss:
            best_rss, best = rss, comm

    resolved = best or _unescape_unit(dirname).split(".")[0]
    _scope_names[cache_key] = resolved
    if len(_scope_names) > 512:               # bounded; scopes come and go
        _scope_names.pop(next(iter(_scope_names)))
    return resolved


def merge_apps(apps):
    """Fold scopes that are the same application into one row.

    Rates and totals add; peaks and stalls take the worst member, because "this
    application stalled 12% of the interval" is answered by its worst scope,
    not by an average that dilutes it.
    """
    merged = {}
    order = []
    for app in apps:
        key = app.get("key") or app["unit"]
        existing = merged.get(key)
        if existing is None:
            entry = dict(app)
            entry["scopes"] = 1
            merged[key] = entry
            order.append(key)
            continue
        existing["mem"] += app["mem"]
        # A high-water mark is not additive: two scopes that peaked at
        # different moments never held the sum of their peaks at once.
        existing["memPeak"] = max(existing["memPeak"], app["memPeak"])
        existing["cpu"] = round(existing["cpu"] + app["cpu"], 1)
        existing["procs"] += app["procs"]
        existing["oomKills"] += app["oomKills"]
        existing["ioStall"] = max(existing["ioStall"], app["ioStall"])
        existing["memStall"] = max(existing["memStall"], app["memStall"])
        existing["scopes"] += 1
        if "ioBytes" in app and "ioBytes" in existing:
            existing["ioBytes"] = (existing["ioBytes"][0] + app["ioBytes"][0],
                                   existing["ioBytes"][1] + app["ioBytes"][1])
        # Once several scopes are folded together the individual unit name is
        # no longer the whole truth, so say how many there were instead.
        existing["unit"] = "%d scopes" % existing["scopes"]
    return [merged[k] for k in order]


def read_cgroups(previous, elapsed):
    """Per-application CPU, memory, stall and I/O.

    `previous` is the last sample's raw counters, keyed by cgroup path, so CPU
    and stall arrive as rates rather than since-boot totals.
    """
    apps = []
    counters = {}

    for root in CGROUP_SCAN_ROOTS:
        base = os.path.join(CGROUP_ROOT, root)
        if not os.path.isdir(base):
            continue
        for dirpath, _, _ in os.walk(base):
            # A slice is a container for scopes; counting both would double.
            # The scan root itself is skipped even though it is a `.service`:
            # `user@1000.service` is the parent of every app scope, and
            # treating it as a leaf would both double-count and — since an
            # earlier version pruned the walk here — hide every application
            # underneath it.
            if dirpath == base or not dirpath.endswith((".scope", ".service")):
                continue

            memory = _cg_int(os.path.join(dirpath, "memory.current"))
            cpu = _cg_keyed(_cg_read(os.path.join(dirpath, "cpu.stat")))
            if memory is None or "usage_usec" not in cpu:
                continue

            pids = (_cg_read(os.path.join(dirpath, "cgroup.procs")) or "").split()
            if not pids:
                continue  # an empty scope is on its way out

            usage = cpu["usage_usec"]
            io_stall = _cg_pressure_total(_cg_read(os.path.join(dirpath, "io.pressure")))
            mem_stall = _cg_pressure_total(_cg_read(os.path.join(dirpath, "memory.pressure")))
            counters[dirpath] = (usage, io_stall, mem_stall)
            before = previous.get(dirpath)

            def rate(now, was, scale):
                if was is None or now is None:
                    return 0.0
                return max(0.0, (now - was) / elapsed * scale)

            events = _cg_keyed(_cg_read(os.path.join(dirpath, "memory.events")))
            basename = os.path.basename(dirpath)
            key, display = app_identity(basename, pids)
            if display is None:
                # A launcher, container or anonymous scope says nothing about
                # its contents, so the label comes from what is running inside.
                display = scope_display_name(basename, pids)
                if key is None:
                    # No identity of its own: the bare name becomes the key, so
                    # a scope named after an app and a scope named after the
                    # launcher that started it still fold together.
                    key = display.lower()
                else:
                    # It has a unique identity but an unreadable one. Keep the
                    # key and disambiguate the label, or two containers of the
                    # same image become two rows with identical names.
                    short = key.split("-")[-1][:8]
                    display = "%s (%s)" % (display, short)
            entry = {
                "name": display,
                "key": key,
                "unit": _unescape_unit(basename),
                "system": root == "system.slice",
                "procs": len(pids),
                "mem": memory,
                # Retroactive facts /proc cannot give: the high-water mark, and
                # whether the kernel has ever had to kill something in here.
                "memPeak": _cg_int(os.path.join(dirpath, "memory.peak")) or memory,
                "oomKills": events.get("oom_kill", 0),
                # usage_usec is microseconds of CPU; /elapsed gives a fraction
                # of one core, ×100 a percentage in the same units as a process.
                "cpu": round(rate(usage, before[0] if before else None, 100.0 / 1e6), 1),
                # Stall totals are microseconds too; as a percentage of the
                # interval this reads "how much of the last two seconds did
                # this app spend waiting rather than working".
                "ioStall": round(min(100.0, rate(io_stall, before[1] if before else None, 100.0 / 1e6)), 1),
                "memStall": round(min(100.0, rate(mem_stall, before[2] if before else None, 100.0 / 1e6)), 1),
            }

            # io.stat only exists where the controller is delegated. Docker
            # delegates it; systemd's user@.service does not by default, which
            # is why per-app bytes need a drop-in but per-app stall does not.
            io = _cg_read(os.path.join(dirpath, "io.stat"))
            if io:
                read_bytes = write_bytes = 0
                for line in io.splitlines():
                    for field in line.split()[1:]:
                        key, _, value = field.partition("=")
                        if key == "rbytes":
                            read_bytes += int(value)
                        elif key == "wbytes":
                            write_bytes += int(value)
                entry["ioBytes"] = (read_bytes, write_bytes)

            apps.append(entry)

    apps.sort(key=lambda a: -a["mem"])
    return apps, counters


def io_delegation_enabled():
    """Whether per-app io.stat is available, for the UI to explain its absence."""
    controllers = _cg_read(os.path.join(
        CGROUP_ROOT, CGROUP_SCAN_ROOTS[0], "cgroup.controllers")) or ""
    return "io" in controllers.split()


# ----------------------------------------------------------------- GPU
#
# There is no /proc for GPUs, so each vendor gets its own reader. Both are
# polled inline with everything else and must stay cheap; a backend that
# cannot answer in well under a millisecond does not belong here.


class NvidiaGpu:
    """NVIDIA via NVML, bound through ctypes.

    nvidia-smi would mean spawning a process per sample; the library it wraps
    answers the same questions in about 0.15ms with no fork at all. Only the
    handful of entry points used here are declared.
    """

    class _Utilization(ctypes.Structure):
        _fields_ = [("gpu", ctypes.c_uint), ("memory", ctypes.c_uint)]

    class _Memory(ctypes.Structure):
        _fields_ = [
            ("total", ctypes.c_ulonglong),
            ("free", ctypes.c_ulonglong),
            ("used", ctypes.c_ulonglong),
        ]

    class _ProcessInfo(ctypes.Structure):
        _fields_ = [
            ("pid", ctypes.c_uint),
            ("usedGpuMemory", ctypes.c_ulonglong),
            ("gpuInstanceId", ctypes.c_uint),
            ("computeInstanceId", ctypes.c_uint),
        ]

    # nvmlClockType_t
    CLOCK_SM = 1
    CLOCK_MEM = 2
    # nvmlPcieUtilCounter_t
    PCIE_TX = 0
    PCIE_RX = 1

    def __init__(self):
        self.lib = ctypes.CDLL("libnvidia-ml.so.1")
        if self.lib.nvmlInit_v2() != 0:
            raise OSError("nvmlInit failed")

        count = ctypes.c_uint()
        if self.lib.nvmlDeviceGetCount_v2(ctypes.byref(count)) != 0:
            raise OSError("nvmlDeviceGetCount failed")

        self.devices = []
        for index in range(count.value):
            handle = ctypes.c_void_p()
            if self.lib.nvmlDeviceGetHandleByIndex_v2(index, ctypes.byref(handle)) != 0:
                continue
            name = ctypes.create_string_buffer(96)
            label = "GPU %d" % index
            if self.lib.nvmlDeviceGetName(handle, name, 96) == 0:
                label = name.value.decode("utf-8", "replace")
            self.devices.append((handle, label))

        if not self.devices:
            raise OSError("no NVML devices")

    def shutdown(self):
        try:
            self.lib.nvmlShutdown()
        except Exception:
            pass

    def _optional(self, function_name, handle, *args):
        """Read one unsigned value, or None if the driver won't answer.

        Fan speed on a passively cooled card, encoder utilisation on a part
        without NVENC, PCIe counters on some laptop GPUs — all legitimately
        unsupported, and none of them worth failing a sample over.
        """
        function = getattr(self.lib, function_name, None)
        if function is None:
            return None
        value = ctypes.c_uint()
        if function(handle, *(list(args) + [ctypes.byref(value)])) != 0:
            return None
        return value.value

    def _engine(self, function_name, handle):
        function = getattr(self.lib, function_name, None)
        if function is None:
            return None
        value = ctypes.c_uint()
        sampling_period = ctypes.c_uint()
        if function(handle, ctypes.byref(value), ctypes.byref(sampling_period)) != 0:
            return None
        return value.value

    def _processes(self, handle):
        """[{pid, name, mem}] for everything holding VRAM on this device.

        Graphics and compute clients are separate NVML lists and a process can
        be on both, so they are merged on pid rather than concatenated.
        """
        merged = {}
        for function_name in ("nvmlDeviceGetGraphicsRunningProcesses_v3",
                              "nvmlDeviceGetComputeRunningProcesses_v3",
                              "nvmlDeviceGetGraphicsRunningProcesses_v2",
                              "nvmlDeviceGetComputeRunningProcesses_v2"):
            function = getattr(self.lib, function_name, None)
            if function is None:
                continue
            count = ctypes.c_uint(GPU_PROCESS_LIMIT)
            infos = (self._ProcessInfo * GPU_PROCESS_LIMIT)()
            if function(handle, ctypes.byref(count), infos) != 0:
                continue
            for index in range(min(count.value, GPU_PROCESS_LIMIT)):
                info = infos[index]
                # NVML reports "not supported" as an all-ones sentinel rather
                # than an error, which would otherwise render as 18 exabytes.
                used = info.usedGpuMemory
                if used >= 0xFFFFFFFFFFFFFFFF:
                    used = 0
                previous = merged.get(info.pid)
                if previous is None or used > previous:
                    merged[info.pid] = used

        rows = []
        for pid, used in merged.items():
            try:
                with open("/proc/%d/comm" % pid) as f:
                    name = f.read().strip()
            except OSError:
                continue  # exited since NVML listed it
            rows.append({"pid": pid, "name": name, "mem": used})

        rows.sort(key=lambda row: -row["mem"])
        return rows

    def sample(self, detailed=False):
        out = []
        for handle, label in self.devices:
            utilization = self._Utilization()
            memory = self._Memory()

            ok = self.lib.nvmlDeviceGetUtilizationRates(handle, ctypes.byref(utilization)) == 0
            self.lib.nvmlDeviceGetMemoryInfo(handle, ctypes.byref(memory))

            power = self._optional("nvmlDeviceGetPowerUsage", handle)
            power_limit = self._optional("nvmlDeviceGetEnforcedPowerLimit", handle)

            # nvmlDeviceGetPcieThroughput samples over a fixed internal window
            # and blocks for ~20ms per counter — two of them cost more than
            # every other reading in this file combined. It and the per-client
            # VRAM list are only ever rendered in the expanded GPU card, so
            # they are only measured while that card is open.
            pcie_tx = pcie_rx = None
            processes = []
            if detailed:
                pcie_tx = self._optional("nvmlDeviceGetPcieThroughput", handle, self.PCIE_TX)
                pcie_rx = self._optional("nvmlDeviceGetPcieThroughput", handle, self.PCIE_RX)
                processes = self._processes(handle)

            out.append({
                "name": label,
                "util": utilization.gpu if ok else 0,
                "memUtil": utilization.memory if ok else 0,
                "memUsed": memory.used,
                "memTotal": memory.total,
                "temp": self._optional("nvmlDeviceGetTemperature", handle, 0),
                "power": round(power / 1000.0, 1) if power is not None else None,
                "powerLimit": round(power_limit / 1000.0) if power_limit is not None else None,
                "encode": self._engine("nvmlDeviceGetEncoderUtilization", handle),
                "decode": self._engine("nvmlDeviceGetDecoderUtilization", handle),
                "smClock": self._optional("nvmlDeviceGetClockInfo", handle, self.CLOCK_SM),
                "memClock": self._optional("nvmlDeviceGetClockInfo", handle, self.CLOCK_MEM),
                "fan": self._optional("nvmlDeviceGetFanSpeed", handle),
                # NVML reports PCIe throughput in KB/s; everything else in this
                # payload is bytes per second.
                "pcieTx": pcie_tx * 1024 if pcie_tx is not None else None,
                "pcieRx": pcie_rx * 1024 if pcie_rx is not None else None,
                "procs": processes,
            })
        return out


class AmdGpu:
    """AMD via amdgpu's sysfs counters, which need no library at all."""

    def __init__(self):
        self.devices = []
        for busy in sorted(glob.glob("/sys/class/drm/card*/device/gpu_busy_percent")):
            device_dir = os.path.dirname(busy)
            label = "GPU"
            try:
                with open(os.path.join(device_dir, "uevent")) as f:
                    for line in f:
                        if line.startswith("DRIVER="):
                            label = line.strip().split("=", 1)[1]
            except OSError:
                pass
            self.devices.append((device_dir, label))
        if not self.devices:
            raise OSError("no amdgpu devices")

    @staticmethod
    def _read_number(path):
        try:
            with open(path) as f:
                return int(f.read().strip())
        except (OSError, ValueError):
            return None

    @staticmethod
    def _hwmon_dir(device_dir):
        """The card's hwmon node, whatever number the kernel gave it.

        hwmon indices are global allocation order, not per-device: on a machine
        whose NVMe drives claim hwmon0 and hwmon1, an amdgpu card is hwmon2 or
        later. Assuming hwmon0 left temperature, power and clocks permanently
        null on any machine with another hwmon device enumerated first.
        """
        nodes = sorted(glob.glob(os.path.join(device_dir, "hwmon", "hwmon*")))
        return nodes[0] if nodes else None

    def sample(self, detailed=False):
        out = []
        for device_dir, label in self.devices:
            used = self._read_number(os.path.join(device_dir, "mem_info_vram_used"))
            total = self._read_number(os.path.join(device_dir, "mem_info_vram_total"))
            hwmon = self._hwmon_dir(device_dir)
            temp = self._read_number(os.path.join(hwmon, "temp1_input")) if hwmon else None
            power = self._read_number(os.path.join(hwmon, "power1_average")) if hwmon else None
            out.append({
                "name": label,
                "util": self._read_number(os.path.join(device_dir, "gpu_busy_percent")) or 0,
                "memUtil": round(used / total * 100) if used and total else 0,
                "memUsed": used or 0,
                "memTotal": total or 0,
                # sysfs reports millidegrees and microwatts.
                "temp": round(temp / 1000) if temp else None,
                "power": round(power / 1000000.0, 1) if power else None,
                # amdgpu exposes no equivalent of NVML's engine, clock, and
                # per-client VRAM queries here. Present-but-null keeps the UI's
                # "hide what the driver can't answer" path identical for both.
                "powerLimit": None,
                "encode": None,
                "decode": None,
                "smClock": self._read_number(os.path.join(hwmon, "freq1_input")) if hwmon else None,
                "memClock": self._read_number(os.path.join(hwmon, "freq2_input")) if hwmon else None,
                "fan": None,
                "pcieTx": None,
                "pcieRx": None,
                "procs": [],
            })
        return out


def detect_gpu():
    """First backend that initialises wins; no GPU is a normal outcome."""
    for backend in (NvidiaGpu, AmdGpu):
        try:
            return backend()
        except Exception:
            continue
    return None


class LazyGpu:
    """Defers GPU initialisation until something actually displays GPU data.

    `nvmlInit_v2` maps the driver and costs ~31MB of RSS plus 0.8ms of every
    sample — more than half the entire always-on budget — and at idle the bar
    widget shows no GPU data at all. So the backend is created on first use and
    released when the last GPU surface closes.
    """

    def __init__(self):
        self._backend = None
        self._tried = False
        self._wanted = False

    def set_wanted(self, wanted):
        if wanted == self._wanted:
            return
        self._wanted = wanted
        if not wanted:
            self.release()

    def release(self):
        backend = self._backend
        self._backend = None
        self._tried = False
        if backend is not None and hasattr(backend, "shutdown"):
            try:
                backend.shutdown()
            except Exception:
                pass

    def sample(self, detailed=False):
        if not self._wanted:
            return None
        if not self._tried:
            self._tried = True
            self._backend = detect_gpu()
        if self._backend is None:
            return None
        try:
            return self._backend.sample(detailed)
        except Exception:
            self.release()
            raise


# ------------------------------------------------------------- thermals
#
# Everything the kernel exposes under /sys/class/hwmon: CPU package and die
# temperatures, drive and RAM sensors, and fan tachometers. Which of those
# exist is entirely a function of what drivers are loaded — a board whose
# super-I/O chip has no in-tree driver reports no fans at all, and that is a
# fact to surface rather than a bug to work around.

# hwmon chip names that report CPU temperature, and the labels each uses for
# the package-level reading, best first.
CPU_CHIPS = ("k10temp", "zenpower", "coretemp")
CPU_PACKAGE_LABELS = ("Tdie", "Package id 0", "Tctl", "CPU Temperature")

# hwmon chip names say what driver is bound, not what the thing is. A strip
# reading "temp1 36°C" four times is useless; these turn the driver name into
# the hardware a person would recognise. Matched by prefix, first hit wins.
CHIP_DISPLAY_NAMES = (
    ("k10temp", "CPU", "cpu"), ("zenpower", "CPU", "cpu"), ("coretemp", "CPU", "cpu"),
    ("nvme", "NVMe", "drive"),
    ("spd5118", "DIMM", "dimm"), ("jc42", "DIMM", "dimm"),
    ("mt7921", "WiFi", "net"), ("iwlwifi", "WiFi", "net"), ("ath1", "WiFi", "net"),
    ("r8169", "Ethernet", "net"), ("igb", "Ethernet", "net"), ("e1000", "Ethernet", "net"),
    ("amdgpu", "GPU", "gpu"), ("nouveau", "GPU", "gpu"),
    ("acpitz", "Board", "board"), ("nct", "Board", "board"), ("it87", "Board", "board"),
)

# Labels that carry no information beyond "this is a sensor".
GENERIC_LABEL_PREFIXES = ("temp", "fan", "in")


NVME_NAMESPACE = re.compile(r"^nvme\d+n\d+$")


def block_devices_for(chip_dir):
    """Block devices an hwmon chip reports temperatures for.

    An NVMe controller's hwmon node carries its namespaces (`nvme0n1`) directly
    under `device/`; a SATA drive's `drivetemp` node carries them under
    `device/block/`. Without this association a surface asking for one drive's
    temperature can only guess, and on a two-drive machine it guesses the first
    one for both — a plausible wrong number, which is the failure mode a monitor
    must never have.
    """
    names = []
    device_dir = os.path.join(chip_dir, "device")
    try:
        for entry in os.listdir(device_dir):
            if NVME_NAMESPACE.match(entry):
                names.append(entry)
    except OSError:
        pass
    try:
        names.extend(os.listdir(os.path.join(device_dir, "block")))
    except OSError:
        pass
    return sorted(set(names))


def display_chip(chip):
    for prefix, name, _ in CHIP_DISPLAY_NAMES:
        if chip.startswith(prefix):
            return name
    return chip


def chip_kind(chip):
    """Coarse category, so a surface can ask for "the DIMM sensors" without
    re-deriving the chip-name knowledge that lives in this file."""
    for prefix, _, kind in CHIP_DISPLAY_NAMES:
        if chip.startswith(prefix):
            return kind
    return "other"


class Thermals:
    """Reads hwmon sensors, with the directory walk done once.

    Discovery — which chips exist, what each sensor is called — cannot change
    without a module load, but the readings change every sample. Doing the walk
    at startup and only reading the `*_input` files afterwards keeps a sample
    to a handful of small reads.
    """

    def __init__(self):
        # Split by cost, not by importance. A CPU die sensor is a register read
        # (~0.02ms); an NVMe sensor is an admin command, a DIMM sensor is an
        # I²C transaction, and a wifi sensor is a firmware round-trip — 0.6 to
        # 3ms each, which together dwarf every other reading in this file. The
        # cheap ones are always sampled; the rest wait until something asks.
        self.cpu_temps = []    # (path, chip, label)
        self.other_temps = []  # (path, chip, label)
        self.fans = []         # (path, chip, label)
        self.cpu_path = None

        # hwmon numbering is allocation order, not a stable identity, so sort to
        # keep the device indices below consistent across boots on one machine.
        for chip_dir in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
            chip = self._read_text(os.path.join(chip_dir, "name")) or "hwmon"
            is_cpu_chip = chip in CPU_CHIPS
            for input_path in sorted(glob.glob(os.path.join(chip_dir, "temp*_input"))):
                prefix = input_path[:-len("_input")]
                label = self._read_text(prefix + "_label") or os.path.basename(prefix)
                entry = (input_path, chip, label, chip_dir)
                (self.cpu_temps if is_cpu_chip else self.other_temps).append(entry)
            # Fan tachometers are port or register reads wherever they exist at
            # all, so they stay on the cheap path.
            for input_path in sorted(glob.glob(os.path.join(chip_dir, "fan*_input"))):
                prefix = input_path[:-len("_input")]
                label = self._read_text(prefix + "_label") or os.path.basename(prefix)
                self.fans.append((input_path, chip, label, chip_dir))

        self.cpu_path = self._find_cpu_package()
        self._assign_names()

    def _assign_names(self):
        """Give every sensor a name a person can act on.

        A driver name plus its own label is usually enough ("CPU Tccd1"), but
        two NVMe drives present the same chip *and* the same label, and a
        board's DIMM sensors are all just `temp1`. Anything still ambiguous
        after that is numbered in discovery order — the order `nvme list` and
        `sensors` use, so the numbers line up with other tools.
        """
        lists = (self.cpu_temps, self.other_temps, self.fans)

        # The index belongs to the *device*, not the sensor: two NVMe drives
        # each reporting "Composite" and "Sensor 2" want to read
        # "NVMe 1 Composite" / "NVMe 2 Composite", not "NVMe Composite 1" and
        # a nonsensical "NVMe Sensor 2 2".
        devices = {}  # pretty name -> [chip_dir, ...] in discovery order
        for entry_list in lists:
            for _, chip, _, chip_dir in entry_list:
                seen_dirs = devices.setdefault(display_chip(chip), [])
                if chip_dir not in seen_dirs:
                    seen_dirs.append(chip_dir)

        for entry_list in lists:
            for index, (path, chip, label, chip_dir) in enumerate(entry_list):
                pretty = display_chip(chip)
                seen_dirs = devices[pretty]
                if len(seen_dirs) > 1:
                    pretty = "%s %d" % (pretty, seen_dirs.index(chip_dir) + 1)
                if label.lower().startswith(GENERIC_LABEL_PREFIXES):
                    name = pretty  # "temp1" says nothing the chip name doesn't
                else:
                    name = label if pretty == label else "%s %s" % (pretty, label)
                entry_list[index] = (path, chip, label, name, block_devices_for(chip_dir))

    @staticmethod
    def _read_text(path):
        try:
            with open(path) as f:
                return f.read().strip()
        except OSError:
            return None

    @staticmethod
    def _read_number(path):
        try:
            with open(path) as f:
                return int(f.read().strip())
        except (OSError, ValueError):
            return None

    def _find_cpu_package(self):
        """The one temperature that means "the CPU", by chip then by label."""
        for chip_name in CPU_CHIPS:
            candidates = [t for t in self.cpu_temps if t[1] == chip_name]
            if not candidates:
                continue
            for label in CPU_PACKAGE_LABELS:
                for entry in candidates:
                    if entry[2] == label:  # (path, chip, label, chip_dir)
                        return entry[0]
            return candidates[0][0]  # unlabelled CPU chip: take its first sensor
        return None

    def sample(self, detailed=False):
        out = {
            "cpu": None,
            "sensors": [],
            "fans": [],
            # Distinguishes "this board reports no fans" from "the fans are at
            # zero RPM", which are very different things to show a user.
            "fansAvailable": len(self.fans) > 0,
        }

        sources = self.cpu_temps + self.other_temps if detailed else self.cpu_temps
        for path, chip, label, name, block_devices in sources:
            millidegrees = self._read_number(path)
            if millidegrees is None:
                continue
            celsius = round(millidegrees / 1000.0, 1)
            if path == self.cpu_path:
                out["cpu"] = celsius
            sensor = {"chip": chip, "kind": chip_kind(chip), "label": label,
                      "name": name, "temp": celsius}
            if block_devices:
                sensor["devices"] = block_devices
            out["sensors"].append(sensor)

        for path, chip, label, name, _ in self.fans:
            rpm = self._read_number(path)
            if rpm is None:
                continue
            out["fans"].append({"chip": chip, "kind": chip_kind(chip), "label": label,
                                "name": name, "rpm": rpm})

        return out


def read_threads(pid):
    """{tid: {...}} for one process. Only ever called for an expanded row."""
    out = {}
    try:
        entries = os.scandir("/proc/%d/task" % pid)
    except OSError:
        return out

    for entry in entries:
        if not entry.name.isdigit():
            continue
        try:
            with open(entry.path + "/stat", "rb") as f:
                raw = f.read()
        except OSError:
            continue
        close = raw.rfind(b")")
        if close < 0:
            continue
        fields = raw[close + 2:].split()
        if len(fields) < 13:
            continue
        try:
            out[int(entry.name)] = {
                "name": raw[raw.find(b"(") + 1:close].decode("utf-8", "replace"),
                "state": fields[0].decode("ascii", "replace"),
                "jiffies": int(fields[11]) + int(fields[12]),
            }
        except (ValueError, IndexError):
            continue
    return out


def read_procs():
    """{pid: {...}} one entry per live process, cheap fields only."""
    out = {}
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        try:
            with open(entry.path + "/stat", "rb") as f:
                raw = f.read()
        except OSError:
            continue  # exited between scandir and open

        # comm is parenthesised and may itself contain spaces or parens, so the
        # numeric fields start after the *last* ')', not the first space.
        close = raw.rfind(b")")
        if close < 0:
            continue
        fields = raw[close + 2:].split()
        if len(fields) < 22:
            continue

        try:
            pid = int(entry.name)
            state = fields[0].decode("ascii", "replace")
            record = {
                "name": raw[raw.find(b"(") + 1:close].decode("utf-8", "replace"),
                "state": state,
                "ppid": int(fields[1]),
                "jiffies": int(fields[11]) + int(fields[12]),  # utime + stime
                "threads": int(fields[17]),
                "rss": int(fields[21]) * PAGE_SIZE,
                "uid": entry.stat().st_uid,
            }
        except (ValueError, IndexError, OSError):
            continue

        # Time spent runnable but not running — pure CPU contention, and the
        # reason a machine can feel slow while every CPU% column reads calm.
        # schedstat field 2; absent only if CONFIG_SCHEDSTATS is off.
        try:
            with open(entry.path + "/schedstat") as f:
                sched = f.read().split()
            if len(sched) >= 2:
                record["runqueue"] = int(sched[1])
        except (OSError, ValueError):
            pass

        # Uninterruptible sleep is the state where signals do nothing, so the
        # only useful thing to show is what the kernel is blocked in. Read for
        # those processes alone — one extra file for a handful of pids.
        if state == "D":
            try:
                with open(entry.path + "/wchan") as f:
                    blocked_in = f.read().strip()
                if blocked_in and blocked_in != "0":
                    record["wchan"] = blocked_in
            except OSError:
                pass

        out[pid] = record
    return out


# Command lines are elided in every surface that shows them, so carrying the
# full 4KB of a browser's argv only inflates the payload.
CMDLINE_CHARS = 220


def read_cmdline(pid, fallback):
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            raw = f.read()
    except OSError:
        return fallback
    if not raw:
        return fallback  # kernel threads have an empty cmdline
    text = raw.replace(b"\x00", b" ").strip().decode("utf-8", "replace")
    return text if len(text) <= CMDLINE_CHARS else text[:CMDLINE_CHARS] + "…"


def busy_percent(current, previous):
    delta_total = current[1] - previous[1]
    if delta_total <= 0:
        return 0.0
    pct = (current[0] - previous[0]) / delta_total * 100.0
    return round(min(100.0, max(0.0, pct)), 1)


def rates(current, previous, elapsed):
    """Per-second deltas for a {key: (a, b)} counter map."""
    out = {}
    for key, (a, b) in current.items():
        prev = previous.get(key)
        if prev is None:
            continue
        # Counters only go backwards when a device is re-created, in which case
        # the delta is meaningless rather than negative.
        out[key] = (
            max(0.0, (a - prev[0]) / elapsed),
            max(0.0, (b - prev[1]) / elapsed),
        )
    return out


class Sampler:
    def __init__(self, interval, want_procs, limit):
        self.interval = interval
        self.want_procs = want_procs
        self.limit = limit
        self.thread_pid = 0
        self.gpu_detail = False
        self.gpu = LazyGpu()
        self.sensor_detail = False
        self.net_detail = False
        self.disk_detail = False
        self.apps_detail = False
        self.group_apps = True
        self.prev_cgroups = {}
        # Forking systemctl costs ~5ms, which is more than the entire rest of a
        # sample. Failed units change rarely, so poll on a slow timer and carry
        # the last answer between polls.
        self.failed_units = []
        self.failed_units_at = 0.0
        self.thermals = Thermals()
        self.recorder = FlightRecorder()
        self.socket_detail = False
        self.open_files_pid = 0
        self.prime()

    def prime(self):
        """Reset every baseline to now, so the next sample measures from here."""
        self.prev_cpu = read_cpu()
        self.prev_net = read_net()
        self.prev_disk = read_disk()
        self.prev_disk_stats = read_disk_stats()
        self.prev_proc_io = {}
        self.prev_procs = read_procs() if self.want_procs else {}
        self.prev_threads = read_threads(self.thread_pid) if self.thread_pid else {}
        # cpu.stat is cumulative and outlives the applications gate, so a
        # baseline taken before the overlay last closed makes the next sample
        # divide however long it was shut by a single interval. Twelve seconds
        # closed is enough to show a browser at several hundred percent for one
        # frame; a minute reads in the thousands. The discarded first return is
        # the rates against an empty baseline — all zero — and the counters are
        # what we actually want.
        self.prev_cgroups = read_cgroups({}, 1.0)[1] if self.apps_detail else {}
        self.prev_time = time.monotonic()

    def sample(self):
        now = time.monotonic()
        elapsed = max(1e-6, now - self.prev_time)

        cpu = read_cpu()
        cores = [
            busy_percent(cpu[i], self.prev_cpu[i])
            for i in range(1, min(len(cpu), len(self.prev_cpu)))
        ]
        # Total jiffies burned across every core this interval. Per-process
        # shares are measured against this, so a process pegging one core of
        # sixteen reads as 100% (of a core) rather than 6% (of the machine) —
        # the htop/btop convention.
        cpu_jiffies = cpu[0][1] - self.prev_cpu[0][1] if self.prev_cpu else 0

        net = read_net()
        disk = read_disk()
        disk_stats = read_disk_stats()
        net_rates = rates(net, self.prev_net, elapsed)
        disk_rates = rates(disk, self.prev_disk, elapsed)

        with open("/proc/loadavg") as f:
            load = [float(v) for v in f.read().split()[:3]]
        with open("/proc/uptime") as f:
            uptime = float(f.read().split()[0])

        out = {
            "interval": round(elapsed, 3),
            "uptime": uptime,
            "cpu": {
                "total": busy_percent(cpu[0], self.prev_cpu[0]) if self.prev_cpu else 0.0,
                "cores": cores,
                "count": len(cores),
                "load": load,
            },
            "mem": read_mem(),
            "pressure": read_pressure(),
            "swaps": read_swaps(),
            "thermal": self.thermals.sample(self.sensor_detail),
            "cpufreq": read_cpufreq(),
            "irq": read_interrupts(),
            "btrfs": read_btrfs(),
            "failedUnits": self.poll_failed_units(),
            "net": {
                "rx": round(sum(r[0] for r in net_rates.values())),
                "tx": round(sum(r[1] for r in net_rates.values())),
                "ifaces": [
                    {"name": name, "rx": round(r[0]), "tx": round(r[1])}
                    for name, r in sorted(net_rates.items())
                ],
                "links": read_links(net.keys(), self.net_detail),
            },
            "disk": {
                "read": round(sum(r[0] for r in disk_rates.values())),
                "write": round(sum(r[1] for r in disk_rates.values())),
                "devices": derive_disk(disk_stats, self.prev_disk_stats, elapsed),
                "filesystems": read_filesystems(),
            },
        }

        if self.net_detail:
            out["sockets"] = read_sockets()

        if self.disk_detail:
            out.update(self.io_table(elapsed))

        if self.socket_detail:
            pids = [int(e.name) for e in os.scandir("/proc") if e.name.isdigit()]
            out["socketCounts"] = {str(k): v for k, v in count_process_sockets(pids).items()}

        if self.open_files_pid:
            details = read_open_files(self.open_files_pid)
            if details is not None:
                out["openFiles"] = details

        if self.apps_detail:
            apps, self.prev_cgroups = read_cgroups(self.prev_cgroups, elapsed)
            if self.group_apps:
                apps = merge_apps(apps)
                apps.sort(key=lambda a: -a["mem"])
            out["apps"] = apps
            out["ioDelegated"] = io_delegation_enabled()

        try:
            devices = self.gpu.sample(self.gpu_detail)
            if devices is not None:
                out["gpu"] = {"devices": devices}
        except Exception as error:
            # A GPU that falls off the bus mid-session (driver reload, eGPU
            # unplug) should cost the panel its GPU card, not its samples.
            out["gpu"] = {"devices": [], "error": str(error)}

        if self.want_procs:
            out.update(self.process_table(cpu_jiffies, elapsed, len(cores)))

        if self.thread_pid:
            out["threadsOf"] = self.thread_pid
            out["threads"] = self.thread_table(cpu_jiffies, len(cores))

        self.prev_cpu = cpu
        self.prev_net = net
        self.prev_disk = disk
        self.prev_disk_stats = disk_stats
        self.prev_time = now
        self.recorder.record(out, now)
        return out

    def process_table(self, cpu_jiffies, elapsed, ncpu):
        """Every process, not a top-N slice.

        The previous version emitted only the busiest `limit` processes, which
        meant the UI could not find — let alone sort by — anything that was not
        already CPU-busy. Searching for a sleeping daemon returned nothing and
        "sort by memory" silently ranked within the CPU top 60. A full scan of
        ~700 processes costs about 14ms, which the process table's own gate
        already covers, so there is no reason to truncate.

        `limit` now governs only how many command lines are resolved, since
        that is the part that scales badly and matters least for the long tail.
        """
        procs = read_procs()
        ncpu = ncpu or os.cpu_count() or 1
        scale = (100.0 * ncpu / cpu_jiffies) if cpu_jiffies > 0 else 0.0
        elapsed_ms = max(1e-6, elapsed) * 1000.0

        rows = []
        running = 0
        blocked = 0
        threads = 0
        for pid, cur in procs.items():
            threads += cur["threads"]
            if cur["state"] == "R":
                running += 1
            elif cur["state"] == "D":
                blocked += 1

            previous = self.prev_procs.get(pid)
            # A recycled pid looks like a huge negative jump; comparing comm
            # catches the common case and costs one string compare.
            delta = 0
            wait_ms = 0.0
            if previous is not None and previous["name"] == cur["name"]:
                delta = max(0, cur["jiffies"] - previous["jiffies"])
                if "runqueue" in cur and "runqueue" in previous:
                    # Nanoseconds of runnable-but-not-running this interval,
                    # as a share of the interval: 100% means it spent the whole
                    # time waiting for a CPU.
                    waited = max(0, cur["runqueue"] - previous["runqueue"])
                    wait_ms = waited / 1e6

            row = {
                "pid": pid,
                "ppid": cur["ppid"],
                "name": cur["name"],
                "user": username(cur["uid"]),
                "cpu": round(delta * scale, 1),
                "rss": cur["rss"],
                "threads": cur["threads"],
                "state": cur["state"],
                "wait": round(min(100.0, wait_ms / elapsed_ms * 100.0), 1),
            }
            if "wchan" in cur:
                row["wchan"] = cur["wchan"]
            rows.append(row)

        self.prev_procs = procs
        # Emitted busiest-first. The sampler no longer truncates, but callers
        # that show only the first few rows — the bar panel's "top processes" —
        # need that to mean the busiest few rather than whichever pids scandir
        # happened to return first.
        rows.sort(key=lambda r: (-r["cpu"], -r["rss"]))

        # Command lines only for the rows most likely to be looked at. Sorting
        # by CPU and by memory separately means a memory hog that never uses
        # the CPU still gets one.
        detailed = set()
        for key in ("cpu", "rss"):
            ranked = sorted(rows, key=lambda r: -r[key])
            detailed.update(r["pid"] for r in ranked[:self.limit])
        for row in rows:
            if row["pid"] in detailed:
                row["cmd"] = read_cmdline(row["pid"], row["name"])

        return {
            "procs": rows,
            "procCount": len(procs),
            "procRunning": running,
            "procBlocked": blocked,
            "threadCount": threads,
            "cmdResolved": len(detailed),
        }

    def poll_failed_units(self):
        now = time.monotonic()
        if now - self.failed_units_at > FAILED_UNIT_POLL_SEC:
            self.failed_units = read_failed_units()
            self.failed_units_at = now
        return self.failed_units

    def io_table(self, elapsed):
        """Processes ranked by block I/O over the interval.

        Unlike network, the kernel does account for this per process — but only
        to the process's owner, so a normal session sees its own processes and
        not root's. The readable/total counts go along so the UI can say which
        it is showing rather than implying the list is complete.
        """
        pids = [int(e.name) for e in os.scandir("/proc") if e.name.isdigit()]
        current = read_process_io(pids)

        rows = []
        for pid, (read_bytes, write_bytes) in current.items():
            before = self.prev_proc_io.get(pid)
            if before is None:
                continue
            read_rate = max(0, read_bytes - before[0]) / elapsed
            write_rate = max(0, write_bytes - before[1]) / elapsed
            if read_rate <= 0 and write_rate <= 0:
                continue
            try:
                with open("/proc/%d/comm" % pid) as f:
                    name = f.read().strip()
            except OSError:
                continue
            rows.append({
                "pid": pid,
                "name": name,
                "read": round(read_rate),
                "write": round(write_rate),
            })

        self.prev_proc_io = current
        rows.sort(key=lambda row: -(row["read"] + row["write"]))
        return {
            "ioProcs": rows[:20],
            "ioReadable": len(current),
            "ioTotal": len(pids),
        }

    def thread_table(self, cpu_jiffies, ncpu):
        """Per-thread CPU for the one expanded process, busiest first."""
        threads = read_threads(self.thread_pid)
        ncpu = ncpu or os.cpu_count() or 1
        scale = (100.0 * ncpu / cpu_jiffies) if cpu_jiffies > 0 else 0.0

        rows = []
        for tid, cur in threads.items():
            previous = self.prev_threads.get(tid)
            delta = 0
            if previous is not None and previous["name"] == cur["name"]:
                delta = max(0, cur["jiffies"] - previous["jiffies"])
            rows.append({
                "tid": tid,
                "name": cur["name"],
                "state": cur["state"],
                "cpu": round(delta * scale, 1),
            })

        self.prev_threads = threads
        rows.sort(key=lambda row: (-row["cpu"], row["tid"]))
        # Deliberately not `limit`: that setting bounds a list of every process
        # on the machine, and a user who trimmed it to ten still wants to see
        # more than ten of a browser's threads.
        return rows[:THREAD_LIMIT]

    def handle(self, line):
        """Apply one stdin command. Returns True if baselines need re-priming."""
        parts = line.split()
        if not parts:
            return False
        command = parts[0]
        argument = parts[1] if len(parts) > 1 else ""

        if command == "quit":
            raise SystemExit(0)
        if command == "procs":
            want = argument == "on"
            if want == self.want_procs:
                return False
            self.want_procs = want
            if not want:
                # Closing a view needs no baseline; re-priming for it would
                # reset every other one and cost an off-cadence sample.
                self.prev_procs = {}
                return False
            return True
        if command == "interval":
            try:
                self.interval = min(60.0, max(0.25, float(argument)))
            except ValueError:
                pass
            return False
        if command == "limit":
            try:
                self.limit = min(2000, max(1, int(argument)))
            except ValueError:
                pass
            return False
        if command == "history":
            # Its own line, so the shell can seed its graphs with everything
            # recorded before this session started.
            print(json.dumps({"history": self.recorder.load()},
                             separators=(",", ":")), flush=True)
            return False
        if command == "gpu":
            # Nothing shows GPU data at idle, so the driver is not mapped until
            # a surface that displays it opens.
            self.gpu.set_wanted(argument == "on")
            return False
        if command == "sockets":
            want = argument == "on"
            if want == self.socket_detail:
                return False
            self.socket_detail = want
            return False
        if command == "openfiles":
            try:
                pid = 0 if argument in ("", "off") else int(argument)
            except ValueError:
                return False
            if pid == self.open_files_pid:
                return False
            self.open_files_pid = max(0, pid)
            return False
        if command == "groupapps":
            # Off shows one row per systemd scope instead of one per application.
            self.group_apps = argument != "off"
            return False
        if command == "apps":
            # Per-application accounting from cgroups, for the Applications view.
            want = argument == "on"
            if want == self.apps_detail:
                return False
            self.apps_detail = want
            if not want:
                # Nothing reads these again until the view reopens, and by then
                # they describe a window that has already closed. A missing
                # baseline reads as 0% for one sample; a stale one reads as
                # hundreds or thousands of percent.
                self.prev_cgroups = {}
                return False
            # Unlike the other detail gates, this one is measured as a rate, so
            # it needs the same re-prime the process table asks for.
            return True
        if command == "diskdetail":
            # Per-process block I/O, for the expanded disk card.
            want = argument == "on"
            if want == self.disk_detail:
                return False
            self.disk_detail = want
            if not want:
                self.prev_proc_io = {}
                return False
            return True
        if command == "netdetail":
            # Error counters and the socket table, for the expanded network card.
            want = argument == "on"
            if want == self.net_detail:
                return False
            self.net_detail = want
            return False
        if command == "sensors":
            # Turns on the off-CPU hwmon sensors (NVMe, DIMM, wifi), each of
            # which costs a bus transaction, while a view is listing them.
            want = argument == "on"
            if want == self.sensor_detail:
                return False
            self.sensor_detail = want
            return False
        if command == "gpudetail":
            # Turns on the expensive GPU readings (PCIe throughput, per-client
            # VRAM) while the expanded GPU card is showing them.
            want = argument == "on"
            if want == self.gpu_detail:
                return False
            self.gpu_detail = want
            return False
        if command == "threads":
            # `threads <pid>` expands one process; `threads off` (or 0) collapses.
            try:
                pid = 0 if argument in ("", "off") else int(argument)
            except ValueError:
                return False
            if pid == self.thread_pid:
                return False
            self.thread_pid = max(0, pid)
            if not self.thread_pid:
                self.prev_threads = {}
                return False
            return True
        return False


class StdinLines:
    """Line reader that never leaves data in a Python-level buffer.

    select() reports on the file descriptor, but sys.stdin.readline() reads
    through an object buffer on top of it. When two commands arrive in the same
    chunk — which is exactly what happens when a surface closes and another
    opens in the same frame, sending `procs off` then `procs on` — readline()
    hands back the first and keeps the second, while select() correctly reports
    that the fd has nothing new. The second command then sits unread until
    something else happens to arrive. Reading the fd directly keeps the
    readiness check and the reader talking about the same bytes.
    """

    def __init__(self, fd):
        self.fd = fd
        self.buffer = b""
        self.closed = False

    def read_available(self):
        try:
            chunk = os.read(self.fd, 65536)
        except OSError:
            self.closed = True
            return []
        if not chunk:
            self.closed = True
            return []
        self.buffer += chunk
        lines = self.buffer.split(b"\n")
        self.buffer = lines.pop()  # trailing partial line waits for more bytes
        return [line.decode("utf-8", "replace") for line in lines]


def main():
    interval = 2.0
    want_procs = False
    limit = 60

    # A malformed invocation should not take the sampler down: the stdin
    # handlers already ignore values they cannot parse, and argv gets the same
    # treatment, including a trailing flag with no value at all.
    args = sys.argv[1:]
    for i, arg in enumerate(args):
        value = args[i + 1] if i + 1 < len(args) else ""
        try:
            if arg == "--interval":
                interval = min(60.0, max(0.25, float(value)))
            elif arg == "--limit":
                limit = min(2000, max(1, int(value)))
            elif arg == "--procs":
                want_procs = value == "on"
        except ValueError:
            pass

    sampler = Sampler(interval, want_procs, limit)
    stdin = StdinLines(sys.stdin.fileno())
    # Re-priming after `procs on` throws away the interval already elapsed, so
    # emit the first table sooner than a full period to keep panel-open snappy.
    deadline = time.monotonic() + sampler.interval

    while True:
        while True:
            timeout = deadline - time.monotonic()
            if timeout <= 0:
                break
            readable, _, _ = select.select([stdin.fd], [], [], timeout)
            if not readable:
                break
            lines = stdin.read_available()
            if stdin.closed:
                return  # the shell went away; so do we
            # Every command in this chunk is applied before the next readiness
            # check, so a batch re-primes once rather than once per line. The
            # list is built eagerly: any() over a generator would stop at the
            # first command that changed state and drop the rest of the batch.
            changed = [sampler.handle(line) for line in lines]
            if any(changed):
                sampler.prime()
                deadline = time.monotonic() + min(sampler.interval, 0.6)

        try:
            print(json.dumps(sampler.sample(), separators=(",", ":")), flush=True)
        except BrokenPipeError:
            return
        deadline = time.monotonic() + sampler.interval


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
