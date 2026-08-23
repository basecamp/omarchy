#!/usr/bin/env python3
"""Prove Chromium CSD min/max/close with an absolute pointer.

Never AbsPointer Cursor. Tuck Cursor aside and restore it in finally.
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import time
from pathlib import Path

HELPER = Path(__file__).resolve().parent / "hyprbars-pointer-proof.py"
spec = importlib.util.spec_from_file_location("hyprbars_pointer_proof", HELPER)
mod = importlib.util.module_from_spec(spec)
sys.modules["hyprbars_pointer_proof"] = mod
spec.loader.exec_module(mod)

AbsPointer = mod.AbsPointer
ProofError = mod.ProofError
as_user = mod.as_user
client_by_addr = mod.client_by_addr
clients = mod.clients
grim = mod.grim
hypr = mod.hypr
monitor_size = mod.monitor_size
wait_until = mod.wait_until
tuck_cursor_windows = mod.tuck_cursor_windows
restore_cursor_windows = mod.restore_cursor_windows

CHROME_CLASSES = {"chromium", "google-chrome", "google-chrome-stable", "brave-browser", "vivaldi-stable"}
TITLE = "omarchy-w0-csd"


def chrome_windows() -> list[dict]:
  out = []
  for c in clients():
    klass = str(c.get("class") or "").lower()
    if klass == "cursor":
      continue
    if klass in CHROME_CLASSES or "chrom" in klass:
      out.append(c)
  return out


def proof_chrome() -> dict | None:
  for c in chrome_windows():
    title = str(c.get("title") or "")
    if TITLE in title:
      return c
    if str(c.get("initialTitle") or "") == TITLE:
      return c
  titled = [c for c in chrome_windows() if TITLE in str(c.get("title") or "")]
  return titled[0] if titled else None


def csd_button(win: dict, which: str) -> tuple[int, int]:
  x, y = win["at"]
  w = win["size"][0]
  # Measured from grim of Google Chrome CSD on this desktop:
  # float 1200x740 glyphs at y+25..34, centers x+w-65 / -33 / -16
  # maximized 1920x1032 glyphs at y+15..24, centers x+w-84 / -52 / -18
  # A single x+w-33 hits max while floating and close once maximized.
  maximized = y < 24 or win.get("fullscreen") == 1
  if maximized:
    cy = y + 18
    offsets = {"close": 18, "max": 52, "min": 84}
  else:
    offsets = {"close": 16, "max": 33, "min": 65}
    # After restore the min dash center (y+29) is a hit-test hole.
    # y+22 is inside the button on both a fresh float and a restored float.
    cy = y + (22 if which == "min" else 29)
  if which not in offsets:
    raise ProofError(f"unknown CSD button {which}")
  return x + w - offsets[which], cy


def close_proof_chromes() -> None:
  for c in chrome_windows():
    title = f"{c.get('title') or ''} {c.get('initialTitle') or ''}"
    if TITLE in title:
      as_user(["omarchy-shell", "window", "close", c["address"]], wait=True, timeout=5)


def chrome_bin() -> str:
  home = Path.home()
  candidates = [
    str(home / ".local/opt/google/chrome/google-chrome"),
    "google-chrome-stable",
    "google-chrome",
    "chromium",
    "brave",
  ]
  for cand in candidates:
    if cand.startswith("/") and Path(cand).is_file():
      return cand
    probe = as_user(["bash", "-lc", f"command -v {cand}"], wait=True, timeout=5)
    if probe.returncode == 0 and (probe.stdout or "").strip():
      return (probe.stdout or "").strip()
  raise ProofError("no Chromium-family browser on PATH for CSD caption proof")


def click_verified(pointer: AbsPointer, x: int, y: int) -> list[int]:
  gw, gh = monitor_size()
  pointer.move(x, y, gw, gh)
  time.sleep(0.15)

  def cursor_near():
    raw = hypr("cursorpos").replace(" ", "")
    try:
      cx, cy = (int(p) for p in raw.split(","))
    except ValueError:
      return False
    return abs(cx - x) <= 12 and abs(cy - y) <= 12

  wait_until(f"abs pointer reached {x},{y}", 4, cursor_near)
  raw = hypr("cursorpos").replace(" ", "")
  pointer.button(True)
  time.sleep(0.08)
  pointer.button(False)
  time.sleep(0.25)
  try:
    cx, cy = (int(p) for p in raw.split(","))
    return [cx, cy]
  except ValueError:
    return [x, y]


def launch_chrome() -> None:
  close_proof_chromes()
  time.sleep(0.4)
  bin_name = chrome_bin()
  html = Path("/tmp/omarchy-w0-csd.html")
  html.write_text(f"<!doctype html><title>{TITLE}</title><body>{TITLE}</body>\n", encoding="utf-8")
  flags = (
    "--ozone-platform=wayland --ozone-platform-hint=wayland "
    "--enable-features=WaylandWindowDecorations --no-first-run --new-window"
  )
  profile = f"/tmp/omarchy-w0-csd-profile-{os.getpid()}-{int(time.time())}"
  as_user(
    ["bash", "-lc", f"nohup {bin_name} {flags} --user-data-dir={profile} {html.as_uri()} >/tmp/omarchy-w0-csd.log 2>&1 & disown"],
    wait=True,
  )
  wait_until("Chromium CSD proof window", 25, lambda: proof_chrome() is not None)


def main() -> int:
  report: dict = {"ok": False}
  pointer = None
  saved_cursor = []
  chrome_addr = None
  try:
    saved_cursor = tuck_cursor_windows()
    report["cursor_tucked"] = [c.get("address") for c in saved_cursor]
    as_user(["omarchy-shell", "notifications", "dismissAll"], wait=True, timeout=5)

    launch_chrome()
    chrome = proof_chrome()
    if not chrome:
      raise ProofError("Chromium CSD proof window did not map")
    chrome_addr = chrome["address"]
    if str(chrome.get("class") or "").lower() == "cursor":
      raise ProofError("refusing to AbsPointer Cursor")
    as_user(["omarchy-shell", "window", "moveTo", chrome_addr, "360", "146"], wait=True, timeout=5)
    as_user(["omarchy-shell", "window", "resizeTo", chrome_addr, "1200", "740"], wait=True, timeout=5)
    as_user(["omarchy-shell", "window", "focus", chrome_addr], wait=True, timeout=5)
    time.sleep(1.2)
    chrome = client_by_addr(chrome_addr)
    if not chrome:
      raise ProofError("Chromium vanished before CSD clicks")
    if (chrome.get("size") or [0, 0])[0] < 1100:
      raise ProofError(f"CSD proof window is too narrow for caption buttons: {chrome.get('size')}")
    report["chrome"] = {"addr": chrome_addr, "class": chrome.get("class"), "at": chrome.get("at"), "size": chrome.get("size")}
    grim("/tmp/w0-csd-before.png")

    pointer = AbsPointer()
    gw, gh = monitor_size()
    report["monitor"] = [gw, gh]
    mx, my = csd_button(chrome, "max")
    report["max_click_aim"] = [mx, my]
    report["max_click_cursor"] = click_verified(pointer, mx, my)
    wait_until(
      "csd maximize click maximizes",
      8,
      lambda: (w := client_by_addr(chrome_addr)) is not None and w.get("fullscreen") == 1,
    )
    time.sleep(0.6)
    grim("/tmp/w0-csd-max.png")
    maximized = client_by_addr(chrome_addr)
    report["max_click"] = {
      "at": None if not maximized else maximized.get("at"),
      "size": None if not maximized else maximized.get("size"),
      "fullscreen": None if not maximized else maximized.get("fullscreen"),
    }
    as_user(["omarchy-shell", "notifications", "dismissAll"], wait=True, timeout=5)
    mx, my = csd_button(maximized, "max")
    report["max_restore_aim"] = [mx, my]
    report["max_restore_cursor"] = click_verified(pointer, mx, my)
    def restored():
      w = client_by_addr(chrome_addr) or proof_chrome()
      if w is None:
        return False
      if w.get("hidden") is True:
        raise ProofError(f"CSD restore click minimized instead: {w.get('at')} {w.get('size')} fs={w.get('fullscreen')}")
      return w.get("fullscreen") in (0, False, None)

    wait_until("csd maximize click restores", 8, restored)
    if client_by_addr(chrome_addr) is None:
      remapped = proof_chrome()
      if remapped:
        chrome_addr = remapped["address"]
    time.sleep(0.6)
    grim("/tmp/w0-csd-max-restore.png")

    chrome = client_by_addr(chrome_addr)
    if not chrome:
      raise ProofError("Chromium vanished after CSD restore")
    as_user(["omarchy-shell", "notifications", "dismissAll"], wait=True, timeout=5)
    as_user(["omarchy-shell", "window", "focus", chrome_addr], wait=True, timeout=5)
    time.sleep(0.3)
    chrome = client_by_addr(chrome_addr)
    if not chrome:
      raise ProofError("Chromium vanished before CSD minimize")
    mix, miy = csd_button(chrome, "min")
    report["min_click_aim"] = [mix, miy]
    gw, gh = monitor_size()
    pointer.move(mix, miy, gw, gh)
    time.sleep(0.15)
    pointer.button(True)
    time.sleep(0.08)
    pointer.button(False)
    wait_until(
      "csd minimize click hides",
      8,
      lambda: (w := client_by_addr(chrome_addr)) is not None and w.get("hidden") is True,
    )
    grim("/tmp/w0-csd-min.png")
    ping = as_user(["omarchy-shell", "window", "restore", chrome_addr], wait=True, timeout=5)
    if ping.returncode != 0:
      raise ProofError(f"restore after CSD minimize failed: {ping.stdout} {ping.stderr}")
    wait_until(
      "restore after CSD minimize",
      8,
      lambda: (w := client_by_addr(chrome_addr)) is not None and w.get("hidden") in (False, None),
    )

    chrome = client_by_addr(chrome_addr)
    cx, cy = csd_button(chrome, "close")
    report["close_aim"] = [cx, cy]
    report["close_cursor"] = click_verified(pointer, cx, cy)
    wait_until("CSD close unmaps Chromium proof window", 8, lambda: client_by_addr(chrome_addr) is None)
    report["close"] = "unmapped"
    grim("/tmp/w0-csd-close.png")
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
      restore_cursor_windows(saved_cursor)
    except Exception:
      pass
    try:
      hypr("eval", 'hl.device({ name = "qemu-qemu-usb-tablet", enabled = true })')
      hypr("eval", 'hl.device({ name = "imexps/2-generic-explorer-mouse", enabled = true })')
      hypr("eval", 'hl.device({ name = "ydotoold-virtual-device-1", enabled = true })')
    except Exception:
      pass
    if chrome_addr and client_by_addr(chrome_addr):
      try:
        as_user(["omarchy-shell", "window", "close", chrome_addr], wait=True, timeout=5)
      except Exception:
        pass


if __name__ == "__main__":
  sys.exit(main())
