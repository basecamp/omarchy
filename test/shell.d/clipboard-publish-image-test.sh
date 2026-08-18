#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

ROOT="$ROOT" /usr/bin/python3 <<'PY'
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
cat >"$TEST_TMPDIR/bin/setsid" <<'SH'
#!/bin/bash
[[ $1 == "-f" ]] && shift
printf '%s\n' "$*" >"$PUBLISH_LOG"
printf '%s' "${*: -1}" >"$PUBLISHED_PATH"
SH

cat >"$TEST_TMPDIR/bin/wl-paste" <<'SH'
#!/bin/bash
if [[ $1 == "--list-types" ]]; then
  printf 'image/png\ntext/plain\napplication/x-omarchy-file-backed-image\n'
elif [[ $1 == "--type" && $2 == "text/plain" ]]; then
  cat "$PUBLISHED_PATH"
fi
SH
chmod +x "$TEST_TMPDIR/bin/setsid" "$TEST_TMPDIR/bin/wl-paste"
printf 'image' >"$TEST_TMPDIR/image.png"

PUBLISH_LOG="$TEST_TMPDIR/publish" PUBLISHED_PATH="$TEST_TMPDIR/published-path" PATH="$TEST_TMPDIR/bin:$PATH" OMARCHY_PATH="$ROOT" \
  "$ROOT/bin/omarchy-clipboard-publish-image" image/png "$TEST_TMPDIR/image.png"
[[ $(<"$TEST_TMPDIR/publish") == "$ROOT/shell/plugins/clipboard/publish-image.py image/png $TEST_TMPDIR/image.png" ]] || fail "image publisher detaches its clipboard provider"
pass "image publisher detaches and waits for its clipboard provider"

IFS= read -r publisher_shebang <"$ROOT/shell/plugins/clipboard/publish-image.py"
[[ $publisher_shebang == "#!/usr/bin/python3" ]] || fail "image publisher uses the system Python runtime"
pass "image publisher uses the system Python runtime"
