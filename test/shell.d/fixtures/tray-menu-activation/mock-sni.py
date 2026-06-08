#!/usr/bin/env python

import os
import sys
import time
import traceback

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib


ITEM_PATH = "/StatusNotifierItem"
MENU_PATH = "/StatusNotifierItem/Menu"


def variant(value):
  return dbus.Variant(value)


class StatusNotifierItem(dbus.service.Object):
  def __init__(self, bus):
    super().__init__(bus, ITEM_PATH)

  @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
  def Get(self, interface, prop):
    return variant(self.GetAll(interface)[prop])

  @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
  def GetAll(self, interface):
    if interface != "org.kde.StatusNotifierItem":
      return {}

    return dbus.Dictionary({
      "Category": "ApplicationStatus",
      "Id": "omarchy-test-tray",
      "Title": "omarchy-test-tray",
      "Status": "Active",
      "WindowId": dbus.Int32(0),
      "IconName": "dialog-information",
      "IconThemePath": "",
      "Menu": dbus.ObjectPath(MENU_PATH),
      "ItemIsMenu": dbus.Boolean(False),
      "ToolTip": dbus.Struct((
        "",
        dbus.Array([], signature="(iiay)"),
        "omarchy-test-tray",
        "",
      ), signature=None),
    }, signature="sv")

  @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv")
  def Set(self, interface, prop, value):
    return

  @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
  def ContextMenu(self, x, y):
    return

  @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
  def Activate(self, x, y):
    return

  @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
  def SecondaryActivate(self, x, y):
    return

  @dbus.service.method("org.kde.StatusNotifierItem", in_signature="is")
  def Scroll(self, delta, orientation):
    return


class DBusMenu(dbus.service.Object):
  def __init__(self, bus, event_path):
    super().__init__(bus, MENU_PATH)
    self.event_path = event_path

  @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
  def Get(self, interface, prop):
    return variant(self.GetAll(interface)[prop])

  @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
  def GetAll(self, interface):
    if interface != "com.canonical.dbusmenu":
      return {}
    return dbus.Dictionary({
      "Version": dbus.UInt32(3),
      "TextDirection": "ltr",
      "Status": "normal",
      "IconThemePath": dbus.Array([], signature="s"),
    }, signature="sv")

  @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv")
  def Set(self, interface, prop, value):
    return

  @dbus.service.method("com.canonical.dbusmenu", in_signature="i", out_signature="b")
  def AboutToShow(self, item_id):
    return False

  @dbus.service.method("com.canonical.dbusmenu", in_signature="ai", out_signature="aiai")
  def AboutToShowGroup(self, item_ids):
    return ([], [])

  @dbus.service.method("com.canonical.dbusmenu", in_signature="iias", out_signature="u(ia{sv}av)")
  def GetLayout(self, parent_id, recursion_depth, property_names):
    print("GetLayout", int(parent_id), int(recursion_depth), list(property_names), flush=True)
    child = (
      dbus.Int32(2),
      dbus.Dictionary({"label": "Sign in", "enabled": True}, signature="sv"),
      dbus.Array([], signature="v"),
    )
    root = (
      dbus.Int32(0),
      dbus.Dictionary({"children-display": "submenu"}, signature="sv"),
      dbus.Array([dbus.Struct(child, signature=None, variant_level=1)], signature="v"),
    )
    return (dbus.UInt32(1), dbus.Struct(root, signature=None))

  @dbus.service.method("com.canonical.dbusmenu", in_signature="aias", out_signature="a(ia{sv})")
  def GetGroupProperties(self, item_ids, property_names):
    return []

  @dbus.service.method("com.canonical.dbusmenu", in_signature="is", out_signature="v")
  def GetProperty(self, item_id, name):
    return variant("")

  @dbus.service.method("com.canonical.dbusmenu", in_signature="isvu")
  def Event(self, item_id, event_id, data, timestamp):
    print("Event", int(item_id), str(event_id), flush=True)
    if int(item_id) == 2 and str(event_id) == "clicked":
      with open(self.event_path, "w", encoding="utf-8") as handle:
        handle.write("clicked\n")

  @dbus.service.method("com.canonical.dbusmenu", in_signature="a(isvu)", out_signature="ai")
  def EventGroup(self, events):
    for item_id, event_id, data, timestamp in events:
      self.Event(item_id, event_id, data, timestamp)
    return []


def register_with_watcher(bus):
  watcher = dbus.Interface(
    bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher"),
    "org.kde.StatusNotifierWatcher",
  )
  watcher.RegisterStatusNotifierItem(ITEM_PATH)


def main():
  try:
    return run()
  except Exception:
    traceback.print_exc()
    return 1


def run():
  event_path = os.environ["OMARCHY_TRAY_MENU_EVENT_RESULT"]
  ready_path = os.environ["OMARCHY_TRAY_MENU_READY"]

  DBusGMainLoop(set_as_default=True)
  bus = dbus.SessionBus()
  dbus.service.BusName("org.omarchy.TestStatusNotifier", bus)

  StatusNotifierItem(bus)
  DBusMenu(bus, event_path)

  for _ in range(50):
    try:
      register_with_watcher(bus)
      with open(ready_path, "w", encoding="utf-8") as handle:
        handle.write("ready\n")
      break
    except dbus.DBusException:
      time.sleep(0.1)
  else:
    print("timed out registering StatusNotifierItem", file=sys.stderr)
    return 1

  GLib.MainLoop().run()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
