import shlex
import shutil

from gi import require_version

require_version("Nautilus", "4.1")

from gi.repository import GObject, Gio, Nautilus


SUPPORTED_MIME_PREFIXES = ("image/", "video/")
SUPPORTED_EXTENSIONS = {
    ".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".avif",
    ".mp4", ".mov", ".m4v", ".mkv", ".webm", ".avi",
}


class TranscodeAction(GObject.GObject, Nautilus.MenuProvider):
    def _launch_transcode(self, paths):
        wrapper = shutil.which("omarchy-launch-floating-terminal-with-presentation")
        binary = shutil.which("omarchy-transcode")
        if not wrapper or not binary:
            return

        if len(paths) == 1:
            cmd = shlex.join([binary, paths[0]])
        else:
            cmd = "; ".join(
                f"echo {shlex.quote(f'Transcoding {path}')} && "
                f"{shlex.join([binary, path])} || true"
                for path in paths
            )

        Gio.Subprocess.new([wrapper, cmd], Gio.SubprocessFlags.NONE)

    def _is_supported(self, file):
        mime = file.get_mime_type() or ""
        if mime.startswith(SUPPORTED_MIME_PREFIXES):
            return True

        location = file.get_location()
        if not location:
            return False
        path = location.get_path() or ""
        lower = path.lower()
        return any(lower.endswith(ext) for ext in SUPPORTED_EXTENSIONS)

    def _selected_paths(self, files):
        paths = []
        seen = set()

        for file in files:
            if file.is_directory():
                continue
            if not self._is_supported(file):
                continue
            location = file.get_location()
            if not location:
                continue
            path = location.get_path()
            if path and path not in seen:
                seen.add(path)
                paths.append(path)
        return paths

    def _make_item(self, paths):
        label = "Transcode" if len(paths) == 1 else f"Transcode {len(paths)} items"
        item = Nautilus.MenuItem(
            name="OmarchyTranscodeNautilus::transcode",
            label=label,
            icon="media-playback-start",
        )
        item.connect("activate", self._on_activate, paths)
        return item

    def _on_activate(self, _menu, paths):
        self._launch_transcode(paths)

    def _tools_available(self):
        return bool(
            shutil.which("omarchy-launch-floating-terminal-with-presentation")
            and shutil.which("omarchy-transcode")
        )

    def get_file_items(self, *args):
        files = args[0] if len(args) == 1 else args[1]
        if not self._tools_available():
            return []

        paths = self._selected_paths(files)
        if not paths:
            return []

        return [self._make_item(paths)]
