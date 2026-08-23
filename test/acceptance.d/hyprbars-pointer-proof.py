#!/usr/bin/env python3
"""Prove hyprbars and Alt+Tab cards with one absolute pointer.

Relative uinput (ydotool) can move hyprctl cursorpos while button events stay
on another seat (QEMU usb-tablet / PS/2). That is not a mouse proof. This
helper creates an ABS pointer, the same class as a USB tablet, and fails if
/dev/uinput cannot be opened — it does not skip.
"""

from __future__ import annotations

import json
import os
import pwd
import struct
import subprocess
import sys
import time

UINPUT_MAX_NAME_SIZE = 80
ABS_CNT = 64
BUS_USB = 3
UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_SET_ABSBIT = 0x40045567
UI_SET_PROPBIT = 0x4004556e
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
BTN_LEFT = 0x110
ABS_X, ABS_Y = 0, 1
SYN_REPORT = 0
ABS_MAX = 32767
INPUT_PROP_DIRECT = 1


def session_user() -> str:
  for key in ("SUDO_USER", "USER", "LOGNAME"):
    val = os.environ.get(key) or ""
    if val and val != "root":
      return val
  return pwd.getpwuid(os.getuid()).pw_name


USER_NAME = session_user()
USER_UID = pwd.getpwnam(USER_NAME).pw_uid
USER_HOME = pwd.getpwnam(USER_NAME).pw_dir
OMARCHY_PATH = os.environ.get("OMARCHY_PATH") or os.path.join(USER_HOME, "omarchy7ultimate")


class ProofError(RuntimeError):
  pass


def hypr_env() -> dict[str, str]:
  env = os.environ.copy()
  runtime = f"/run/user/{USER_UID}"
  sig = os.popen(f"ls -t {runtime}/hypr 2>/dev/null | head -1").read().strip()
  env.update({
    "PATH": f"/usr/bin:/bin:{OMARCHY_PATH}/bin",
    "OMARCHY_PATH": OMARCHY_PATH,
    "XDG_RUNTIME_DIR": runtime,
    "WAYLAND_DISPLAY": os.environ.get("WAYLAND_DISPLAY") or "wayland-1",
    "HOME": USER_HOME,
    "HYPRLAND_INSTANCE_SIGNATURE": sig,
    "LC_ALL": "C.UTF-8",
  })
  return env


def hypr(*args: str) -> str:
  return subprocess.check_output(["hyprctl", *args], env=hypr_env(), text=True).strip()


def as_user(args: list[str], wait: bool = True, timeout: float | None = 20) -> subprocess.CompletedProcess[str]:
  env = hypr_env()
  if os.getuid() == 0:
    cmd = ["runuser", "-u", USER_NAME, "--", "env"]
    for key in ("PATH", "OMARCHY_PATH", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "HOME", "HYPRLAND_INSTANCE_SIGNATURE", "LC_ALL"):
      cmd.append(f"{key}={env[key]}")
    cmd.extend(args)
  else:
    cmd = args
  if wait:
    return subprocess.run(cmd, env=env, text=True, capture_output=True, timeout=timeout)
  subprocess.Popen(cmd, env=env, start_new_session=True)
  return subprocess.CompletedProcess(cmd, 0, "", "")


def clients() -> list[dict]:
  return json.loads(hypr("-j", "clients") or "[]")


def feet() -> list[dict]:
  return [c for c in clients() if c.get("class") == "foot"]


def wait_until(desc: str, seconds: float, fn) -> None:
  deadline = time.time() + seconds
  last = None
  while time.time() < deadline:
    try:
      if fn():
        return
    except Exception as e:
      last = e
    time.sleep(0.15)
  raise ProofError(f"timed out waiting for {desc}: {last}")


class AbsPointer:
  def __init__(self) -> None:
    if not os.path.exists("/dev/uinput"):
      raise ProofError("/dev/uinput is missing; relative ydotool is not this gate")
    try:
      self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    except OSError as e:
      raise ProofError(f"cannot open /dev/uinput ({e}); relative ydotool is not this gate") from e
    import fcntl

    def ioctl(req, arg=None):
      if arg is None:
        fcntl.ioctl(self.fd, req)
      else:
        fcntl.ioctl(self.fd, req, arg)

    for bit in (EV_KEY, EV_ABS, EV_SYN):
      ioctl(UI_SET_EVBIT, bit)
    ioctl(UI_SET_KEYBIT, BTN_LEFT)
    ioctl(UI_SET_ABSBIT, ABS_X)
    ioctl(UI_SET_ABSBIT, ABS_Y)
    try:
      ioctl(UI_SET_PROPBIT, INPUT_PROP_DIRECT)
    except OSError:
      pass
    name_str = f"omarchy-w0-abs-{os.getpid()}-{int(time.time())}"
    name = name_str.encode()[: UINPUT_MAX_NAME_SIZE - 1]
    name = name + b"\0" * (UINPUT_MAX_NAME_SIZE - len(name))
    absmax = [0] * ABS_CNT
    absmin = [0] * ABS_CNT
    absfuzz = [0] * ABS_CNT
    absflat = [0] * ABS_CNT
    absmax[ABS_X] = ABS_MAX
    absmax[ABS_Y] = ABS_MAX
    blob = name + struct.pack("HHHH I", BUS_USB, 0x04D9, os.getpid() & 0xFFFF, 1, 0)
    blob += struct.pack(f"{ABS_CNT}i", *absmax)
    blob += struct.pack(f"{ABS_CNT}i", *absmin)
    blob += struct.pack(f"{ABS_CNT}i", *absfuzz)
    blob += struct.pack(f"{ABS_CNT}i", *absflat)
    os.write(self.fd, blob)
    ioctl(UI_DEV_CREATE)
    time.sleep(0.5)
    self.name = name_str

  def emit(self, etype: int, code: int, value: int) -> None:
    now = time.time()
    sec = int(now)
    usec = int((now - sec) * 1e6)
    os.write(self.fd, struct.pack("llHHi", sec, usec, etype, code, value))

  def move(self, x: int, y: int, gw: int = 1920, gh: int = 1080) -> None:
    ax = int(round(x / max(gw - 1, 1) * ABS_MAX))
    ay = int(round(y / max(gh - 1, 1) * ABS_MAX))
    self.emit(EV_ABS, ABS_X, ax)
    self.emit(EV_ABS, ABS_Y, ay)
    self.emit(EV_SYN, SYN_REPORT, 0)

  def button(self, down: bool) -> None:
    self.emit(EV_KEY, BTN_LEFT, 1 if down else 0)
    self.emit(EV_SYN, SYN_REPORT, 0)

  def click(self, x: int, y: int) -> None:
    self.move(x, y)
    time.sleep(0.12)
    self.button(True)
    time.sleep(0.12)
    self.button(False)

  def drag(self, x1: int, y1: int, x2: int, y2: int, steps: int = 16) -> None:
    self.move(x1, y1)
    time.sleep(0.12)
    self.button(True)
    time.sleep(0.08)
    for i in range(1, steps + 1):
      x = x1 + (x2 - x1) * i // steps
      y = y1 + (y2 - y1) * i // steps
      self.move(x, y)
      time.sleep(0.02)
    time.sleep(0.08)
    self.button(False)

  def close(self) -> None:
    # UI_DEV_DESTROY can block on this kernel/libinput pairing. Closing the
    # fd is enough for the helper to exit; udev removes the node shortly after.
    try:
      os.close(self.fd)
    except OSError:
      pass


def card_center(index: int, count: int, gw: int, gh: int) -> tuple[int, int]:
  """Center of an Alt+Tab card. Switcher panel is 120px cards, 8px gap, 40px pad, height 160, centered."""
  n = max(1, count)
  row_w = 120 * n + 8 * (n - 1)
  row_x = gw / 2 - row_w / 2
  x = int(row_x + index * 128 + 60)
  y = int(gh / 2)
  return x, y


def monitor_size() -> tuple[int, int]:
  mons = json.loads(hypr("-j", "monitors") or "[]")
  focused = next((m for m in mons if m.get("focused")), mons[0])
  return int(focused["width"]), int(focused["height"])


def launch_feet(n: int) -> None:
  as_user(["pkill", "-x", "foot"], wait=True)
  time.sleep(0.4)
  for i in range(n):
    as_user(["bash", "-lc", f"nohup foot >/tmp/omarchy-foot-{i}.log 2>&1 & disown"], wait=True)
    time.sleep(0.45)
  wait_until(f"{n} foot windows", 12, lambda: len(feet()) >= n)


def layer_named(ns: str) -> bool:
  data = json.loads(hypr("-j", "layers") or "{}")
  blob = json.dumps(data)
  return ns in blob


def grim(path: str) -> None:
  as_user(["grim", path], wait=True)


def pin_session_monitor() -> None:
  mons = json.loads(hypr("-j", "monitors") or "[]")
  focused = next((m for m in mons if m.get("focused")), mons[0] if mons else None)
  if not focused:
    return
  name = focused.get("name") or ""
  if name == "HDMI-A-1":
    hypr("eval", 'hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "0x0", scale = 1 })')
    try:
      hypr("eval", 'hl.monitor({ output = "DP-1", disabled = true })')
    except Exception:
      pass
    return
  if name:
    hypr("eval", f'hl.monitor({{ output = "{name}", mode = "1920x1080@60", position = "0x0", scale = 1 }})')


def cycle_snapshot() -> dict:
  proc = as_user(["omarchy-shell", "window", "cycleSnapshot"], wait=True, timeout=5)
  if proc.returncode != 0:
    raise ProofError(f"cycleSnapshot failed: {proc.stdout} {proc.stderr}")
  raw = (proc.stdout or "").strip()
  try:
    data = json.loads(raw)
  except json.JSONDecodeError as e:
    raise ProofError(f"cycleSnapshot not JSON: {raw!r}") from e
  if not isinstance(data, dict):
    raise ProofError(f"cycleSnapshot was not an object: {raw!r}")
  return data


def main() -> int:
  report: dict = {"ok": False}
  pointer = None
  try:
    pin_session_monitor()
  except Exception:
    pass
  try:
    as_user(["omarchy-shell", "window", "commitCycle"], wait=True, timeout=5)
    as_user(["omarchy-shell", "shell", "hide", "omarchy.ultimate-task-switcher"], wait=True, timeout=5)

    launch_feet(2)
    addrs = [c["address"] for c in feet()]
    report["switcher_addrs"] = addrs
    last = addrs[-1]
    ping = as_user(["omarchy-shell", "window", "focus", last], wait=True)
    if ping.returncode != 0:
      raise ProofError(f"focus failed: {ping.stdout} {ping.stderr}")
    time.sleep(0.3)
    before = json.loads(hypr("-j", "activewindow") or "{}")
    report["switcher_before"] = {"addr": before.get("address"), "class": before.get("class")}
    ping = as_user(["omarchy-shell", "window", "cycleNext"], wait=True)
    if ping.returncode != 0:
      raise ProofError(f"cycleNext failed: {ping.stdout} {ping.stderr}")
    wait_until("task switcher overlay", 8, lambda: layer_named("omarchy-task-switcher"))
    time.sleep(2.0)
    grim("/tmp/w0-c-switcher.png")
    snap = cycle_snapshot()
    report["cycle"] = snap
    cycle_list = list(snap.get("list") or [])
    cycle_idx = int(snap.get("index") or 0)
    if len(cycle_list) < 2:
      raise ProofError(f"need at least two cycle cards to pick a different window: {snap}")
    if cycle_idx < 0 or cycle_idx >= len(cycle_list):
      raise ProofError(f"highlighted cycle index is out of range: {snap}")
    want = cycle_list[cycle_idx]
    if want == last:
      raise ProofError(f"cycleNext kept the focused address highlighted: {snap}")
    # Create the ABS pointer after the overlay is mapped. A device that exists
    # before the layer maps does not deliver buttons onto this Quickshell surface.
    pointer = AbsPointer()
    gw, gh = monitor_size()
    report["monitor"] = [gw, gh]
    click_x, click_y = card_center(cycle_idx, len(cycle_list), gw, gh)
    report["card_aim"] = [click_x, click_y]
    report["card_want"] = want
    pointer.move(click_x, click_y, gw, gh)
    time.sleep(0.25)
    def cursor_near():
      raw = hypr("cursorpos").replace(" ", "")
      try:
        cx, cy = (int(p) for p in raw.split(","))
      except ValueError:
        return False
      return abs(cx - click_x) <= 16 and abs(cy - click_y) <= 16
    wait_until("abs pointer reached the highlighted card", 4, cursor_near)
    pointer.button(True)
    time.sleep(0.3)
    pointer.button(False)
    time.sleep(0.6)
    if layer_named("omarchy-task-switcher"):
      raise ProofError("Alt+Tab card click left omarchy-task-switcher mapped; MouseArea did not pick")
    active = json.loads(hypr("-j", "activewindow") or "{}")
    report["switcher_active"] = {"addr": active.get("address"), "class": active.get("class")}
    if active.get("address") != want:
      raise ProofError(f"card click did not activate the highlighted address {want}: {report['switcher_active']}")
    grim("/tmp/w0-c-switcher-picked.png")

    as_user(["omarchy-shell", "shell", "hide", "omarchy.ultimate-task-switcher"], wait=True, timeout=5)
    launch_feet(1)
    foot = feet()[0]
    addr = foot["address"]
    x, y = foot["at"]
    w, h = foot["size"]
    report["foot0"] = {"addr": addr, "at": [x, y], "size": [w, h]}
    barx, bary = x + w // 2, y - 16
    pointer.drag(barx, bary, barx + 140, bary + 90)
    time.sleep(0.45)
    moved = next((c for c in feet() if c["address"] == addr), None)
    if not moved:
      raise ProofError("window vanished during title-bar drag")
    dx = abs(moved["at"][0] - x)
    dy = abs(moved["at"][1] - y)
    report["drag"] = {"from": [x, y], "to": moved["at"], "delta": [dx, dy]}
    if dx <= 8 and dy <= 8:
      raise ProofError(f"title-bar drag did not move more than 8px: {report['drag']}")
    grim("/tmp/w0-c-drag.png")

    as_user(["omarchy-shell", "window", "restoreNormal", addr], wait=True, timeout=5)
    time.sleep(0.6)
    floated = next((c for c in feet() if c["address"] == addr), None)
    if not floated:
      raise ProofError("window vanished before Aero drag")
    fx, fy = floated["at"]
    fw = floated["size"][0]
    pointer.drag(fx + fw // 2, fy - 16, gw // 2, 4, steps=24)
    time.sleep(0.7)
    topped = next((c for c in feet() if c["address"] == addr), None)
    report["aero_top"] = {"at": None if not topped else topped.get("at"), "size": None if not topped else topped.get("size"), "fullscreen": None if not topped else topped.get("fullscreen")}
    if not topped or topped.get("fullscreen") != 1:
      raise ProofError(f"title-bar drag to the top edge did not maximize: {report['aero_top']}")
    grim("/tmp/w0-g-aero-top.png")
    tx, ty = topped["at"]
    tw = topped["size"][0]
    pointer.drag(tx + tw // 2, max(8, ty - 16), gw // 2, 400, steps=24)
    time.sleep(0.7)
    away = next((c for c in feet() if c["address"] == addr), None)
    report["aero_away"] = {"at": None if not away else away.get("at"), "size": None if not away else away.get("size"), "fullscreen": None if not away else away.get("fullscreen")}
    if not away or away.get("fullscreen") not in (0, False, None):
      raise ProofError(f"drag away from the top edge did not restore: {report['aero_away']}")
    grim("/tmp/w0-g-aero-away.png")

    rx, ry = away["at"]
    rw, rh = away["size"]
    pointer.drag(rx + rw + 2, ry + max(48, rh // 2), rx + rw + 90, ry + max(48, rh // 2), steps=18)
    time.sleep(0.45)
    resized = next((c for c in feet() if c["address"] == addr), None)
    report["resize"] = {"from": [rw, rh], "to": None if not resized else resized.get("size")}
    if not resized or resized["size"][0] < rw + 24:
      raise ProofError(f"edge resize did not grow the window: {report['resize']}")

    x2, y2 = resized["at"]
    w2 = resized["size"][0]
    closex, closey = x2 + w2 - 16, y2 - 16
    report["close_aim"] = [closex, closey]
    pointer.click(closex, closey)
    wait_until("hyprbars close unmaps the aimed foot", 8, lambda: all(c["address"] != addr for c in feet()))
    report["close"] = "unmapped"
    grim("/tmp/w0-c-close.png")
    report["ok"] = True
    print(json.dumps(report, indent=2))
    return 0
  except Exception as e:
    report["error"] = str(e)
    print(json.dumps(report, indent=2), file=sys.stderr)
    print(json.dumps(report, indent=2))
    return 1
  finally:
    if pointer is not None:
      pointer.close()
    try:
      as_user(["omarchy-shell", "shell", "hide", "omarchy.ultimate-task-switcher"], wait=True, timeout=5)
    except Exception:
      pass
    try:
      hypr("eval", 'hl.device({ name = "qemu-qemu-usb-tablet", enabled = true })')
      hypr("eval", 'hl.device({ name = "imexps/2-generic-explorer-mouse", enabled = true })')
      hypr("eval", 'hl.device({ name = "ydotoold-virtual-device-1", enabled = true })')
    except Exception:
      pass


if __name__ == "__main__":
  sys.exit(main())
