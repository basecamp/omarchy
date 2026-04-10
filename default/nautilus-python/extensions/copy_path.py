from gi import require_version

require_version("Nautilus", "4.1")
require_version("Gdk", "4.0")

from gi.repository import GObject, Gdk, Nautilus


class CopyPathAction(GObject.GObject, Nautilus.MenuProvider):
    def _copy_to_clipboard(self, value):
        display = Gdk.Display.get_default()
        if not display:
            return

        clipboard = display.get_clipboard()
        clipboard.set(value)

    def _copy_file_paths(self, files):
        paths = []

        for file in files:
            location = file.get_location()
            if not location:
                continue

            path = location.get_path()
            if path and path not in paths:
                paths.append(path)

        if paths:
            self._copy_to_clipboard("\n".join(paths))

    def _copy_folder_path(self, folder):
        location = folder.get_location()
        if not location:
            return

        path = location.get_path()
        if path:
            self._copy_to_clipboard(path)

    def _build_item(self, name, label, callback, payload):
        item = Nautilus.MenuItem(name=name, label=label, icon="edit-copy")
        item.connect("activate", callback, payload)
        return item

    def _on_copy_files(self, _menu, files):
        self._copy_file_paths(files)

    def _on_copy_folder(self, _menu, folder):
        self._copy_folder_path(folder)

    def get_file_items(self, *args):
        files = args[0] if len(args) == 1 else args[1]

        if not files:
            return []

        label = "Copy Path" if len(files) == 1 else "Copy Paths"

        return [
            self._build_item(
                "CopyPathNautilus::copy_file_paths",
                label,
                self._on_copy_files,
                files,
            )
        ]

    def get_background_items(self, *args):
        current_folder = args[0] if len(args) == 1 else args[1]

        return [
            self._build_item(
                "CopyPathNautilus::copy_current_folder",
                "Copy Current Folder Path",
                self._on_copy_folder,
                current_folder,
            )
        ]
