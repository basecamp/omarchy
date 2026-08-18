import shutil

from gi import require_version

require_version("Nautilus", "4.1")

from gi.repository import GObject, Gio, Nautilus


def _resolve_launch_command():
    launcher = shutil.which("uwsm-app")
    terminal = shutil.which("xdg-terminal-exec")

    if not launcher or not terminal:
        return None

    return [launcher, "--", terminal]


# PATH does not change under a running Files session, so resolve once at import
# rather than on every menu build.
LAUNCH_COMMAND = _resolve_launch_command()


class OpenInTerminalAction(GObject.GObject, Nautilus.MenuProvider):
    def _launch_terminal(self, path):
        # xdg-terminal-exec resolves the terminal the same way `omarchy default
        # terminal` sets it, and --dir works whether or not the entry declares a
        # working-directory flag: it falls back to chdir before exec. That keeps
        # this working across alacritty, foot, ghostty and kitty alike.
        Gio.Subprocess.new(
            LAUNCH_COMMAND + [f"--dir={path}"],
            Gio.SubprocessFlags.NONE,
        )

    def _directory_path(self, file):
        if not file or not file.is_directory():
            return None

        location = file.get_location()
        if not location:
            return None

        # Remote and virtual locations (trash:, sftp:) have no local path to
        # hand a terminal.
        return location.get_path()

    def _make_item(self, path):
        item = Nautilus.MenuItem(
            name="OmarchyTerminalNautilus::open_in_terminal",
            label="Open in Terminal",
            icon="utilities-terminal",
        )
        item.connect("activate", self._on_activate, path)
        return item

    def _on_activate(self, _menu, path):
        self._launch_terminal(path)

    def _items_for(self, file):
        # Offering an entry that cannot launch anything is worse than offering
        # none, so stay out of the menu unless the launcher is really there.
        if not LAUNCH_COMMAND:
            return []

        path = self._directory_path(file)
        if not path:
            return []

        return [self._make_item(path)]

    def get_file_items(self, *args):
        files = args[0] if len(args) == 1 else args[1]

        # Only a lone directory names an unambiguous target; a file selection is
        # already served by the background item for the folder it sits in.
        if len(files) != 1:
            return []

        return self._items_for(files[0])

    def get_background_items(self, *args):
        folder = args[0] if len(args) == 1 else args[1]
        return self._items_for(folder)
