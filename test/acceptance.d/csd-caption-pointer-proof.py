#!/usr/bin/env python3
"""Prove Chromium CSD min/max/close with an absolute pointer.

Never AbsPointer Cursor. Tuck Cursor aside and restore it in finally.
"""

from __future__ import annotations

import importlib.util
import json
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
  # Chromium CSD draws min/max/close inside the top-right of the surface.
  cy = y + 16
  if which == "close":
    return x + w - 18, cy
  if which == "max":
    return x + w - 50, cy
  if which == "min":
    return x + w - 82, cy
  raise ProofError(f"unknown CSD button {which}")


def launch_chrome() -> None:
  existing = proof_chrome()
  if existing:
    return
  bin_name = None
  for cand in ("chromium", "google-chrome-stable", "google-chrome", "brave"):
    probe = as_user(["bash", "-lc", f"command -v {cand}"], wait=True, timeout=5)
    if probe.returncode == 0 and (probe.stdout or "").strip():
      bin_name = cand
      break
  if not bin_name:
    raise ProofError("no Chromium-family browser on PATH for CSD caption proof")
  html = Path("/tmp/omarchy-w0-csd.html")
  html.write_text(f"<!doctype html><title>{TITLE}</title><body>{TITLE}</body>\n", encoding="utf-8")
  flags = (
    "--ozone-platform=wayland --ozone-platform-hint=wayland "
    "--enable-features=WaylandWindowDecorations --no-first-run --new-window"
  )
  as_user(
    ["bash", "-lc", f"nohup {bin_name} {flags} --user-data-dir=/tmp/omarchy-w0-csd-profile {html.as_uri()} >/tmp/omarchy-w0-csd.log 2>&1 & disown"],
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

    launch_chrome()
    chrome = proof_chrome()
    if not chrome:
      raise ProofError("Chromium CSD proof window did not map")
    chrome_addr = chrome["address"]
    if str(chrome.get("class") or "").lower() == "cursor":
      raise ProofError("refusing to AbsPointer Cursor")
    as_user(["omarchy-shell", "window", "moveTo", chrome_addr, "520", "80"], wait=True, timeout=5)
    as_user(["omarchy-shell", "window", "resizeTo", chrome_addr, "900", "640"], wait=True, timeout=5)
    as_user(["omarchy-shell", "window", "focus", chrome_addr], wait=True, timeout=5)
    time.sleep(1.2)
    chrome = client_by_addr(chrome_addr)
    if not chrome:
      raise ProofError("Chromium vanished before CSD clicks")
    report["chrome"] = {"addr": chrome_addr, "class": chrome.get("class"), "at": chrome.get("at"), "size": chrome.get("size")}
    grim("/tmp/w0-csd-before.png")

    pointer = AbsPointer()
    gw, gh = monitor_size()
    report["monitor"] = [gw, gh]
    mx, my = csd_button(chrome, "max")
    report["max_click_aim"] = [mx, my]
    pointer.quick_click(mx, my)
    wait_until(
      "csd maximize click maximizes",
      8,
      lambda: (w := client_by_addr(chrome_addr)) is not None and w.get("fullscreen") == 1,
    )
    grim("/tmp/w0-csd-max.png")
    maximized = client_by_addr(chrome_addr)
    report["max_click"] = {
      "at": None if not maximized else maximized.get("at"),
      "size": None if not maximized else maximized.get("size"),
      "fullscreen": None if not maximized else maximized.get("fullscreen"),
    }
    mx, my = csd_button(maximized, "max")
    pointer.quick_click(mx, my)
    wait_until(
      "csd maximize click restores",
      8,
      lambda: (w := client_by_addr(chrome_addr)) is not None and w.get("fullscreen") in (0, False, None),
    )
    grim("/tmp/w0-csd-max-restore.png")

    chrome = client_by_addr(chrome_addr)
    mix, miy = csd_button(chrome, "min")
    report["min_click_aim"] = [mix, miy]
    pointer.quick_click(mix, miy)
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
    pointer.quick_click(cx, cy)
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
