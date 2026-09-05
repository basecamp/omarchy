import os
import subprocess

from gi import require_version

require_version("Nautilus", "4.1")

from gi.repository import Gio, GObject, Nautilus


class FileActions(GObject.GObject, Nautilus.MenuProvider):
    def _show_error(self, message):
        subprocess.Popen(
            ["zenity", "--error", "--title=New File", f"--text={message}"],
            start_new_session=True,
        )

    def _new_file(self, _menu, folder_path):
        process = Gio.Subprocess.new(
            [
                "zenity",
                "--entry",
                "--title=New File",
                "--text=Enter a filename (for example, notes.txt):",
                "--ok-label=Create",
            ],
            Gio.SubprocessFlags.STDOUT_PIPE,
        )
        process.communicate_utf8_async(
            None,
            None,
            self._finish_new_file,
            folder_path,
        )

    def _finish_new_file(self, process, result, folder_path):
        _successful, stdout, _stderr = process.communicate_utf8_finish(result)
        if not process.get_successful():
            return

        filename = stdout.rstrip("\n")
        if not filename or filename in {".", ".."} or os.path.basename(filename) != filename:
            self._show_error("Enter a single filename without slashes.")
            return

        path = os.path.join(folder_path, filename)
        try:
            descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
            os.close(descriptor)
        except FileExistsError:
            self._show_error(f"A file named ‘{filename}’ already exists.")
        except OSError as error:
            self._show_error(str(error))
        else:
            subprocess.Popen(
                ["nautilus", "--select", path],
                start_new_session=True,
            )

    def _copy_paths(self, _menu, paths):
        subprocess.run(
            ["wl-copy"],
            input="\n".join(paths),
            text=True,
            check=False,
        )

    def get_background_items(self, *args):
        folder = args[-1]
        location = folder.get_location()
        folder_path = location.get_path() if location else None
        if not folder_path or not os.access(folder_path, os.W_OK):
            return []

        item = Nautilus.MenuItem(
            name="OmarchyFileActionsNautilus::new_file",
            label="New File…",
            icon="document-new-symbolic",
        )
        item.connect("activate", self._new_file, folder_path)
        return [item]

    def get_file_items(self, *args):
        files = args[-1]
        paths = []
        for file_info in files:
            location = file_info.get_location()
            path = location.get_path() if location else None
            if path:
                paths.append(path)

        if not paths:
            return []

        label = "Copy Path" if len(paths) == 1 else "Copy Paths"
        item = Nautilus.MenuItem(
            name="OmarchyFileActionsNautilus::copy_path",
            label=label,
            icon="edit-copy-symbolic",
        )
        item.connect("activate", self._copy_paths, paths)
        return [item]
