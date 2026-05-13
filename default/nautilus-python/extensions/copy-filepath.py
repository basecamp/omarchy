import shutil

from gi import require_version

require_version("Nautilus", "4.1")

from gi.repository import GObject, Gio, Nautilus


class CopyFilePathAction(GObject.GObject, Nautilus.MenuProvider):
    def _selected_paths(self, files):
        paths = []
        seen = set()

        for file in files:
            location = file.get_location()
            if not location:
                continue

            path = location.get_path()
            if path and path not in seen:
                seen.add(path)
                paths.append(path)

        return paths

    def _make_item(self, paths):
        label = "Copy file path" if len(paths) == 1 else "Copy file paths"
        item = Nautilus.MenuItem(
            name="OmarchyCopyFilePath::copy_file_path",
            label=label,
            icon="edit-copy",
        )
        item.connect("activate", self._on_activate, paths)
        return item

    def _on_activate(self, _menu, paths):
        text = "\n".join(paths)

        proc = Gio.Subprocess.new(
            ["wl-copy", "--type", "text/plain"],
            Gio.SubprocessFlags.STDIN_PIPE
            | Gio.SubprocessFlags.STDOUT_SILENCE
            | Gio.SubprocessFlags.STDERR_SILENCE,
        )
        if proc:
            proc.communicate(text.encode("utf-8"), cancellable=None)

    def get_file_items(self, *args):
        files = args[0] if len(args) == 1 else args[1]
        paths = self._selected_paths(files)

        if not paths or not shutil.which("wl-copy"):
            return []

        return [self._make_item(paths)]
