import subprocess
from gi.repository import Nautilus, GObject

class CopyPath(GObject.GObject, Nautilus.MenuProvider):
    def _copy_path(self, menu, files):
        path_list = []
        for f in files:
            location = f.get_location()
            if location is None:
                continue
            path = location.get_path()
            if path is None:
                path = location.get_uri()
            if path is not None:
                path_list.append(path)
        paths = "\n".join(path_list)
        subprocess.Popen(["wl-copy", paths])

    def get_file_items(self, files):
        if not files:
            return []

        item = Nautilus.MenuItem(name="CopyPath::CopyPath", label="Copy Path")
        item.connect("activate", self._copy_path, files)
        return [item]
