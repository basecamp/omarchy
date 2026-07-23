"""Emit activity when an attached Linux gamepad receives meaningful input."""

from __future__ import annotations

import asyncio
import importlib
import sys
import time


EV_KEY = 0x01
EV_REL = 0x02
EV_ABS = 0x03
BTN_JOYSTICK = 0x120
BTN_DIGI = 0x140

SCAN_INTERVAL_SECONDS = 2
REPORT_INTERVAL_SECONDS = 1
AXIS_THRESHOLD_RATIO = 0.02


def capability_code(entry):
  if isinstance(entry, (tuple, list)):
    return int(entry[0])
  return int(entry)


def has_gamepad_buttons(capabilities):
  return any(
    BTN_JOYSTICK <= capability_code(entry) < BTN_DIGI
    for entry in capabilities.get(EV_KEY, [])
  )


def axis_info_from_capabilities(capabilities):
  result = {}
  for entry in capabilities.get(EV_ABS, []):
    if isinstance(entry, (tuple, list)) and len(entry) >= 2:
      result[capability_code(entry)] = entry[1]
  return result


class ActivityFilter:
  def __init__(self, axis_info=None):
    self.axes = {}
    for code, info in (axis_info or {}).items():
      minimum = int(getattr(info, "min", 0))
      maximum = int(getattr(info, "max", minimum))
      flat = max(0, int(getattr(info, "flat", 0)))
      span = max(0, maximum - minimum)
      threshold = max(1, flat, round(span * AXIS_THRESHOLD_RATIO))
      value = int(getattr(info, "value", 0))
      self.axes[int(code)] = [value, threshold]

  def accepts(self, event_type, code, value):
    if event_type == EV_KEY:
      return value > 0

    if event_type == EV_REL:
      return value != 0

    if event_type != EV_ABS:
      return False

    code = int(code)
    value = int(value)
    axis = self.axes.get(code)
    if axis is None:
      self.axes[code] = [value, 1]
      return value != 0

    if abs(value - axis[0]) < axis[1]:
      return False

    axis[0] = value
    return True


class ActivityReporter:
  def __init__(self, minimum_interval=REPORT_INTERVAL_SECONDS, clock=None, stream=None):
    self.minimum_interval = minimum_interval
    self.clock = clock or time.monotonic
    self.stream = stream or sys.stdout
    self.last_reported_at = None

  def report(self):
    now = self.clock()
    if self.last_reported_at is not None and now - self.last_reported_at < self.minimum_interval:
      return False

    print("activity", file=self.stream, flush=True)
    self.last_reported_at = now
    return True


async def watch_device(device, activity_filter, reporter):
  try:
    async for event in device.async_read_loop():
      if activity_filter.accepts(event.type, event.code, event.value):
        reporter.report()
  except asyncio.CancelledError:
    raise
  except OSError:
    pass
  finally:
    device.close()


async def monitor_devices(evdev):
  reporter = ActivityReporter()
  watched = {}
  ignored = set()
  reported_errors = {}

  try:
    while True:
      current = set(evdev.list_devices())
      ignored.intersection_update(current)
      reported_errors = {
        path: message
        for path, message in reported_errors.items()
        if path in current
      }

      retired = []
      for path, task in list(watched.items()):
        if path in current and not task.done():
          continue
        watched.pop(path)
        if not task.done():
          task.cancel()
        retired.append(task)

      if retired:
        await asyncio.gather(*retired, return_exceptions=True)

      pending = current.difference(set(watched), ignored)
      for path in sorted(pending):
        device = None
        try:
          device = evdev.InputDevice(path)
          capabilities = device.capabilities(absinfo=True)
        except OSError as error:
          if device is not None:
            device.close()
          message = str(error)
          if reported_errors.get(path) != message:
            print(f"Unable to inspect {path}: {message}", file=sys.stderr)
            reported_errors[path] = message
          continue

        reported_errors.pop(path, None)
        if not has_gamepad_buttons(capabilities):
          ignored.add(path)
          device.close()
          continue

        name = device.name or path
        print(f"Watching gamepad: {name} ({path})", file=sys.stderr)
        activity_filter = ActivityFilter(axis_info_from_capabilities(capabilities))
        watched[path] = asyncio.create_task(watch_device(device, activity_filter, reporter))

      await asyncio.sleep(SCAN_INTERVAL_SECONDS)
  finally:
    for task in watched.values():
      task.cancel()
    await asyncio.gather(*watched.values(), return_exceptions=True)


def wait_for_evdev():
  warned = False
  while True:
    try:
      return importlib.import_module("evdev")
    except ModuleNotFoundError as error:
      if error.name != "evdev":
        raise
      if not warned:
        print("Waiting for the python-evdev package", file=sys.stderr)
        warned = True
      time.sleep(30)
      importlib.invalidate_caches()


def main():
  evdev = wait_for_evdev()
  try:
    asyncio.run(monitor_devices(evdev))
  except KeyboardInterrupt:
    pass
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
