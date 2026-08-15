import os
import shutil

from gi import require_version

require_version("Nautilus", "4.1")

from gi.repository import GObject, Gio, Nautilus


class SendViaLocalSendAction(GObject.GObject, Nautilus.MenuProvider):
    def _launch_localsend(self, paths):
        command = self._resolve_command()
        if not command:
            return

        if command[-1] == "@@":
            command = command + paths + ["@@"]
        else:
            command = command + paths

        Gio.Subprocess.new(command, Gio.SubprocessFlags.NONE)

    def _resolve_command(self):
        localsend = shutil.which("localsend")
        if localsend:
            return [localsend, "--headless", "send"]

        flatpak = shutil.which("flatpak")
        if flatpak and self._has_flatpak_app(flatpak, "org.localsend.localsend_app"):
            return [
                flatpak,
                "run",
                "--file-forwarding",
                "org.localsend.localsend_app",
                "@@",
            ]

        return None

    def _has_flatpak_app(self, flatpak, app_id):
        process = Gio.Subprocess.new(
            [flatpak, "info", app_id],
            Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE,
        )
        return process.wait_check()

    def _selected_paths(self, files):
        paths = []

        for file in files:
            location = file.get_location()
            if not location:
                continue

            path = location.get_path()
            if path and path not in paths:
                paths.append(path)

        return paths

    def _make_item(self, paths):
        label = (
            "Send via LocalSend" if len(paths) == 1 else "Send selected via LocalSend"
        )
        item = Nautilus.MenuItem(
            name="LocalSendNautilus::send_via_localsend",
            label=label,
            icon="localsend",
        )
        item.connect("activate", self._on_activate, paths)
        return item

    def _on_activate(self, _menu, paths):
        self._launch_localsend(paths)

    def get_file_items(self, *args):
        files = args[0] if len(args) == 1 else args[1]
        paths = self._selected_paths(files)

        if not paths or not self._resolve_command():
            return []

        return [self._make_item(paths)]
