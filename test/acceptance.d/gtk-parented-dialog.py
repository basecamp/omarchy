#!/usr/bin/env python3
"""GTK3 MessageDialog with transient_for + MODAL — the xdg-modal path Nautilus uses."""
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk

Gdk.set_program_class("org.omarchy.w0parent")


def main():
  parent = Gtk.Window(title="W0-Parent")
  parent.set_default_size(880, 560)
  parent.connect("destroy", Gtk.main_quit)
  parent.show_all()
  dialog = Gtk.MessageDialog(
    transient_for=parent,
    modal=True,
    destroy_with_parent=True,
    message_type=Gtk.MessageType.QUESTION,
    buttons=Gtk.ButtonsType.OK_CANCEL,
    text="W0 parented dialog",
  )
  dialog.set_title("W0-Dialog")
  dialog.show_all()
  GLib.timeout_add_seconds(20, Gtk.main_quit)
  Gtk.main()


if __name__ == "__main__":
  main()
