#!/usr/bin/env python3
"""Prove Start closes on outside click and on a second Start-orb click.

The Super key already toggled both ways. Mouse did not: the Start panel was a
440x560 exclusive overlay, so pointer events outside the card never arrived.
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
grim = mod.grim
hypr = mod.hypr
layer_named = mod.layer_named
monitor_size = mod.monitor_size
pin_session_monitor = mod.pin_session_monitor
wait_until = mod.wait_until


def shell(*args: str, timeout: float = 8):
  return as_user(["omarchy-shell", *args], wait=True, timeout=timeout)


def start_open() -> bool:
  return layer_named("omarchy-start")


def hide_start() -> None:
  shell("shell", "hide", "omarchy.ultimate-start")
  time.sleep(0.2)


def summon_start() -> None:
  proc = shell("shell", "summon", "omarchy.ultimate-start", "{}")
  if proc.returncode != 0:
    raise ProofError(f"summon Start failed: {proc.stdout} {proc.stderr}")
  wait_until("Start overlay mapped", 8, start_open)


def click(pointer: AbsPointer, x: int, y: int, gw: int, gh: int) -> None:
  pointer.move(x, y, gw, gh)
  time.sleep(0.2)

  def cursor_near():
    raw = hypr("cursorpos").replace(" ", "")
    try:
      cx, cy = (int(p) for p in raw.split(","))
    except ValueError:
      return False
    return abs(cx - x) <= 16 and abs(cy - y) <= 16

  wait_until(f"abs pointer reached {x},{y}", 4, cursor_near)
  pointer.button(True)
  time.sleep(0.15)
  pointer.button(False)
  time.sleep(0.4)


def main() -> int:
  report: dict = {"ok": False}
  pointer = None
  try:
    pin_session_monitor()
    hide_start()
    wait_until("Start overlay unmapped before proof", 6, lambda: not start_open())

    def fresh_pointer() -> AbsPointer:
      nonlocal pointer
      if pointer is not None:
        pointer.close()
        time.sleep(0.35)
      # Create the ABS pointer after the overlay is mapped. A device that
      # exists before the layer maps does not deliver buttons onto this
      # Quickshell surface.
      pointer = AbsPointer()
      return pointer

    summon_start()
    time.sleep(0.35)
    grim("/tmp/start-open.png")
    gw, gh = monitor_size()
    report["monitor"] = [gw, gh]
    # Card sits at x=8..448, y=(H-48-560)..(H-48). Aim at the desktop center.
    outside_x, outside_y = gw // 2, max(80, gh // 3)
    report["outside"] = [outside_x, outside_y]
    click(fresh_pointer(), outside_x, outside_y, gw, gh)
    if start_open():
      raise ProofError("clicking outside Start left omarchy-start mapped")
    grim("/tmp/start-closed-outside.png")
    report["outside_closed"] = True

    summon_start()
    time.sleep(0.35)
    orb_x, orb_y = 38, gh - 24
    report["orb"] = [orb_x, orb_y]
    click(fresh_pointer(), orb_x, orb_y, gw, gh)
    if start_open():
      raise ProofError("clicking the Start orb again left omarchy-start mapped")
    grim("/tmp/start-closed-orb.png")
    report["orb_closed"] = True

    summon_start()
    time.sleep(0.25)
    card_x, card_y = 24, gh - 48 - 560 + 12
    report["card"] = [card_x, card_y]
    click(fresh_pointer(), card_x, card_y, gw, gh)
    if not start_open():
      raise ProofError("clicking inside the Start card closed it")
    grim("/tmp/start-still-open-card.png")
    report["card_stayed_open"] = True

    proc = shell("shell", "toggle", "omarchy.ultimate-start", "{}")
    if proc.returncode != 0:
      raise ProofError(f"toggle hide failed: {proc.stdout} {proc.stderr}")
    wait_until("Start overlay unmapped after toggle", 6, lambda: not start_open())
    proc = shell("shell", "toggle", "omarchy.ultimate-start", "{}")
    if proc.returncode != 0:
      raise ProofError(f"toggle summon failed: {proc.stdout} {proc.stderr}")
    wait_until("Start overlay mapped after toggle", 8, start_open)
    hide_start()
    wait_until("Start overlay unmapped at end", 6, lambda: not start_open())
    report["toggle_ok"] = True

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
      hide_start()
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
