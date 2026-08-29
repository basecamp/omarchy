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
        self._display_manager = Gdk.DisplayManager.get()
        self._display_opened_handler = 0
        self._settings = None
        self._bus = None
        self._css_path = os.path.join(GLib.get_user_config_dir(), "gtk-4.0", "gtk.css")
        display = self._display_manager.get_default_display()
        if display is None:
            self._display_opened_handler = self._display_manager.connect(
                "display-opened", self._on_display_opened
            )
        else:
            self._initialize(display)

    def _on_display_opened(self, manager, display):
        manager.disconnect(self._display_opened_handler)
        self._display_opened_handler = 0
        self._initialize(display)

    def _initialize(self, display):
        self._display = display
        self._settings = Gtk.Settings.get_for_display(self._display)
        self._settings.connect(
            "notify::gtk-interface-color-scheme", self._on_color_scheme_changed
        )

        try:
            self._bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            self._bus.signal_subscribe(
                None,
                "org.omarchy.Theme",
                "Changed",
                "/org/omarchy/Theme",
                None,
                Gio.DBusSignalFlags.NONE,
                self._on_theme_changed,
            )
        except GLib.Error as error:
            print(
                f"Omarchy GTK theme signal setup failed: {error.message}",
                file=sys.stderr,
            )

        self._reload_css()

    def _on_theme_changed(self, *_args):
        self._reload_css()

    def _on_color_scheme_changed(self, settings, _property):
        if self._provider is not None:
            self._provider.props.prefers_color_scheme = (
                settings.props.gtk_interface_color_scheme
            )

    def _reload_css(self):
        if not os.path.exists(self._css_path):
            if self._provider is not None:
                Gtk.StyleContext.remove_provider_for_display(
                    self._display, self._provider
                )
                self._provider = None
            return

        provider = Gtk.CssProvider()
        provider.props.prefers_color_scheme = (
            self._settings.props.gtk_interface_color_scheme
        )
        parsing_errors = []
        provider.connect(
            "parsing-error",
            lambda _provider, _section, error: parsing_errors.append(error.message),
        )

        try:
            provider.load_from_path(self._css_path)
        except GLib.Error as error:
            print(f"Omarchy GTK theme reload failed: {error.message}", file=sys.stderr)
            return

        if parsing_errors:
            for message in parsing_errors:
                print(f"Omarchy GTK theme parse error: {message}", file=sys.stderr)
            return

        if self._provider is not None:
            Gtk.StyleContext.remove_provider_for_display(self._display, self._provider)

        Gtk.StyleContext.add_provider_for_display(
            self._display,
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_USER,
        )
        self._provider = provider

    def get_file_items(self, _files):
        return []

    def get_background_items(self, _current_folder):
        return []
