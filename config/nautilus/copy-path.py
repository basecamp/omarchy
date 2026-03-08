import subprocess
from gi.repository import Nautilus, GObject

class CopyPath(GObject.GObject, Nautilus.MenuProvider):
    def _copy_path(self, menu, files):
        paths = "\n".join(f.get_location().get_path() for f in files)
        subprocess.Popen(["wl-copy", paths])

    def get_file_items(self, files):
        if not files:
            return []

        item = Nautilus.MenuItem(name="CopyPath::CopyPath", label="Copy Path")
        item.connect("activate", self._copy_path, files)
        return [item]
