#!/usr/bin/python3

import pathlib
import sys

import gi

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")

from gi.repository import Gdk, GLib, Gtk


MARKER_MIME = "application/x-omarchy-file-backed-image"


class ClipboardOwnerProvider(Gdk.ContentProvider):
    __gtype_name__ = "OmarchyClipboardOwnerProvider"

    def __init__(self, provider, on_detach):
        super().__init__()
        self.provider = provider
        self.on_detach = on_detach

    def do_ref_formats(self):
        return self.provider.ref_formats()

    def do_write_mime_type_async(self, mime, stream, priority, cancellable, callback, user_data):
        self.provider.write_mime_type_async(mime, stream, priority, cancellable, callback, user_data)

    def do_write_mime_type_finish(self, result):
        return self.provider.write_mime_type_finish(result)

    def do_detach_clipboard(self, _clipboard):
        self.on_detach()


def clipboard_payloads(mime: str, path: pathlib.Path, image: bytes):
    path_text = str(path).encode()
    return [
        (mime, image),
        ("text/plain;charset=utf-8", path_text),
        ("text/plain", path_text),
        ("text/uri-list", (path.as_uri() + "\r\n").encode()),
        (MARKER_MIME, b"1"),
    ]


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: publish-image.py <mime-type> <path>", file=sys.stderr)
        return 1

    mime, raw_path = sys.argv[1:]
    path = pathlib.Path(raw_path).resolve()
    if not mime.startswith("image/") or not path.is_file():
        return 1
    Gtk.init()
    display = Gdk.Display.get_default()
    if display is None:
        return 1

    clipboard = display.get_clipboard()
    loop = GLib.MainLoop()
    result = 1
    image = path.read_bytes()
    providers = [
        Gdk.ContentProvider.new_for_bytes(payload_mime, GLib.Bytes.new(data))
        for payload_mime, data in clipboard_payloads(mime, path, image)
    ]
    provider = ClipboardOwnerProvider(Gdk.ContentProvider.new_union(providers), loop.quit)

    def claim_clipboard():
        nonlocal result
        if clipboard.set_content(provider):
            result = 0
        else:
            print("Unable to take ownership of the clipboard image", file=sys.stderr)
            loop.quit()
        return GLib.SOURCE_REMOVE

    # Claim from inside the loop so replacement notifications cannot arrive
    # in the gap between taking ownership and starting lifecycle processing.
    GLib.idle_add(claim_clipboard)
    loop.run()
    return result


if __name__ == "__main__":
    raise SystemExit(main())
