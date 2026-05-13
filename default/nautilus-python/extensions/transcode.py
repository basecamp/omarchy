import shlex
import shutil

from gi import require_version

require_version("Nautilus", "4.1")

from gi.repository import GObject, Gio, Nautilus


PICTURE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".avif")
VIDEO_EXTENSIONS = (".mp4", ".mov", ".m4v", ".mkv", ".webm", ".avi")


class TranscodeAction(GObject.GObject, Nautilus.MenuProvider):
    def _media_type(self, file):
        mime = file.get_mime_type() or ""
        if mime.startswith("image/"):
            return "picture"
        if mime.startswith("video/"):
            return "video"

        location = file.get_location()
        if not location:
            return None
        path = (location.get_path() or "").lower()
        if path.endswith(PICTURE_EXTENSIONS):
            return "picture"
        if path.endswith(VIDEO_EXTENSIONS):
            return "video"
        return None

    def _batch_command(self, binary, media_type, paths):
        if media_type == "picture":
            format_options = "jpg png"
            resolution_options = "high medium low"
        else:
            format_options = "mp4 gif"
            resolution_options = "4k 1080p 720p"

        commands = [
            f"format=$(omarchy-menu-select 'Select {media_type} format' {format_options}) || exit 1",
            f"resolution=$(omarchy-menu-select 'Select {media_type} resolution' {resolution_options}) || exit 1",
        ]

        for path in paths:
            commands.append(
                f"echo {shlex.quote(f'Transcoding {path}')} && "
                f"{shlex.join([binary, path])} \"$format\" \"$resolution\" || true"
            )

        return "; ".join(commands)

    def _launch_transcode(self, paths):
        wrapper = shutil.which("omarchy-launch-floating-terminal-with-presentation")
        binary = shutil.which("omarchy-transcode")
        if not wrapper or not binary:
            return

        if len(paths) == 1:
            cmd = shlex.join([binary, paths[0][1]])
        else:
            picture_paths = [path for media_type, path in paths if media_type == "picture"]
            video_paths = [path for media_type, path in paths if media_type == "video"]
            commands = []
            if picture_paths:
                commands.append(self._batch_command(binary, "picture", picture_paths))
            if video_paths:
                commands.append(self._batch_command(binary, "video", video_paths))
            cmd = "; ".join(commands)

        Gio.Subprocess.new([wrapper, cmd], Gio.SubprocessFlags.NONE)

    def _selected_paths(self, files):
        paths = []
        seen = set()

        for file in files:
            if file.is_directory():
                continue
            media_type = self._media_type(file)
            if not media_type:
                continue
            location = file.get_location()
            if not location:
                continue
            path = location.get_path()
            if path and path not in seen:
                seen.add(path)
                paths.append((media_type, path))
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
