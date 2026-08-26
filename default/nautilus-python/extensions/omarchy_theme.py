import os
import sys

from gi import require_version

require_version("Gdk", "4.0")
require_version("Gtk", "4.0")
require_version("Nautilus", "4.1")

from gi.repository import Gdk, Gio, GLib, GObject, Gtk, Nautilus


# Nautilus only instantiates declared provider types. This provider contributes
# no menu rows; it supplies lifecycle access for reloading the process-wide CSS.
class OmarchyThemeExtension(GObject.GObject, Nautilus.MenuProvider):
    def __init__(self):
        super().__init__()
        self._provider = None
        self._display = None
        self._monitor = None
        self._reload_source = 0
        self._css_path = os.path.join(GLib.get_user_config_dir(), "gtk-4.0", "gtk.css")
        GLib.timeout_add(100, self._initialize)

    def _initialize(self):
        self._display = Gdk.Display.get_default()
        if self._display is None:
            return GLib.SOURCE_CONTINUE

        self._reload_css()

        css_dir = Gio.File.new_for_path(os.path.dirname(self._css_path))
        try:
            self._monitor = css_dir.monitor_directory(Gio.FileMonitorFlags.NONE, None)
            self._monitor.connect("changed", self._on_css_changed)
        except GLib.Error as error:
            print(f"Omarchy GTK theme monitor failed: {error.message}", file=sys.stderr)

        return GLib.SOURCE_REMOVE

    def _on_css_changed(self, _monitor, file, other_file, _event_type):
        changed_names = {
            candidate.get_basename()
            for candidate in (file, other_file)
            if candidate is not None
        }
        if not changed_names.intersection({"gtk.css", "omarchy.css"}):
            return

        if self._reload_source:
            GLib.source_remove(self._reload_source)
        self._reload_source = GLib.timeout_add(100, self._reload_css)

    def _reload_css(self):
        self._reload_source = 0
        provider = Gtk.CssProvider()
        parsing_errors = []
        provider.connect(
            "parsing-error",
            lambda _provider, _section, error: parsing_errors.append(error.message),
        )

        try:
            provider.load_from_path(self._css_path)
        except GLib.Error as error:
            print(f"Omarchy GTK theme reload failed: {error.message}", file=sys.stderr)
            return GLib.SOURCE_REMOVE

        if parsing_errors:
            for message in parsing_errors:
                print(f"Omarchy GTK theme parse error: {message}", file=sys.stderr)
            return GLib.SOURCE_REMOVE

        if self._provider is not None:
            Gtk.StyleContext.remove_provider_for_display(self._display, self._provider)

        Gtk.StyleContext.add_provider_for_display(
            self._display,
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_USER,
        )
        self._provider = provider
        return GLib.SOURCE_REMOVE

    def get_file_items(self, _files):
        return []

    def get_background_items(self, _current_folder):
        return []
