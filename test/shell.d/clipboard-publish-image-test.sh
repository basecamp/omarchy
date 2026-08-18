#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

ROOT="$ROOT" python <<'PY'
import importlib.util
import os
import pathlib

root = pathlib.Path(os.environ["ROOT"])
spec = importlib.util.spec_from_file_location(
    "publish_image", root / "shell/plugins/clipboard/publish-image.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

image = b"\x89PNG\r\n\x1a\nclipboard-image"
path = pathlib.Path("/tmp/clipboard image.png")
payloads = dict(module.clipboard_payloads("image/png", path, image))
assert payloads["image/png"] == image
assert payloads["text/plain;charset=utf-8"] == str(path).encode()
assert payloads["text/plain"] == str(path).encode()
assert payloads["text/uri-list"] == (path.resolve().as_uri() + "\r\n").encode()
assert payloads[module.MARKER_MIME] == b"1"
PY
pass "image publisher builds image, path, URI, and marker payloads"

if OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-clipboard-publish-image" unexpected >/dev/null 2>&1; then
  fail "image publisher rejects arguments"
fi
pass "image publisher rejects arguments"

TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT
mkdir -p "$TEST_TMPDIR/bin"
cat >"$TEST_TMPDIR/bin/python" <<'SH'
#!/bin/bash
touch "$PYTHON_CALLED"
SH
chmod +x "$TEST_TMPDIR/bin/python"
printf 'image' >"$TEST_TMPDIR/image.png"

if GDK_BACKEND=wayland WAYLAND_DISPLAY=missing XDG_RUNTIME_DIR="$TEST_TMPDIR" PYTHON_CALLED="$TEST_TMPDIR/python-called" PATH="$TEST_TMPDIR/bin:$PATH" OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-clipboard-publish-image" image/png "$TEST_TMPDIR/image.png" 2>/dev/null; then
  fail "image publisher uses the system Python runtime"
fi
[[ ! -e $TEST_TMPDIR/python-called ]] || fail "image publisher uses the system Python runtime"
pass "image publisher uses the system Python runtime"
