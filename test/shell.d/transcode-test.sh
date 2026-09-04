#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
media_dir="$test_tmp/media folder"
calls="$test_tmp/calls"
mkdir -p "$stub_bin" "$media_dir/nested"
touch "$media_dir/photo one.jpg" "$media_dir/movie one.mov" "$media_dir/notes.txt" "$media_dir/nested/hidden.jpg"

cat >"$stub_bin/file" <<'SH'
#!/bin/bash
case "$3" in
  *.jpg) echo image/jpeg ;;
  *.mov) echo video/quicktime ;;
  *) echo text/plain ;;
esac
SH

cat >"$stub_bin/magick" <<'SH'
#!/bin/bash
printf 'magick:%s\n' "$*" >>"$TEST_CALLS"
[[ $1 == *broken* ]] && exit 1
touch "${!#}"
SH

cat >"$stub_bin/ffmpeg" <<'SH'
#!/bin/bash
printf 'ffmpeg:%s\n' "$*" >>"$TEST_CALLS"
touch "${!#}"
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/wl-copy" <<'SH'
#!/bin/bash
echo clipboard >>"$TEST_CALLS"
SH

chmod +x "$stub_bin"/*

run_transcode() {
  PATH="$stub_bin:$PATH" TEST_CALLS="$calls" "$ROOT/bin/omarchy-transcode" "$@"
}

run_transcode "$media_dir" jpg medium >"$test_tmp/pictures.out"
[[ -f $media_dir/photo\ one-medium.jpg ]] || fail "folder transcoding writes the expected picture output"
[[ ! -f $media_dir/nested/hidden-medium.jpg ]] || fail "folder transcoding only processes direct children"
[[ $(grep -c '^magick:' "$calls") == 1 ]] || fail "picture folder transcoding filters non-picture files"
grep -q 'Skipped 2 unsupported or mismatched item(s).' "$test_tmp/pictures.out" ||
  fail "folder transcoding reports skipped files"
grep -q '^clipboard$' "$calls" && fail "folder transcoding does not copy batch output to the clipboard"
pass "folder transcoding filters pictures and stays non-recursive"

: >"$calls"
run_transcode "$media_dir" mp4 1080p >"$test_tmp/videos.out"
[[ -f $media_dir/movie\ one-1080p.mp4 ]] || fail "folder transcoding writes the expected video output"
grep -q 'ffmpeg:.*-c:a aac -b:a 192k -movflags +faststart' "$calls" ||
  fail "folder transcoding preserves Quattro MP4 encoding options"
grep -q '^clipboard$' "$calls" && fail "video folder transcoding does not copy batch output to the clipboard"
pass "folder transcoding preserves Quattro video encoding"

empty_dir="$test_tmp/empty"
mkdir "$empty_dir"
if run_transcode "$empty_dir" jpg low >"$test_tmp/empty.out" 2>"$test_tmp/empty.err"; then
  fail "folder transcoding fails when no matching files exist"
fi
grep -q 'No supported picture files found' "$test_tmp/empty.err" ||
  fail "folder transcoding explains an empty batch"
pass "folder transcoding rejects an empty batch"

failure_dir="$test_tmp/failures"
mkdir "$failure_dir"
touch "$failure_dir/broken.jpg" "$failure_dir/working.jpg"
: >"$calls"
run_transcode "$failure_dir" jpg low >"$test_tmp/failures.out" 2>"$test_tmp/failures.err"
[[ -f $failure_dir/working-low.jpg ]] || fail "folder transcoding continues after a failed file"
[[ ! -f $failure_dir/broken-low.jpg ]] || fail "folder transcoding does not report failed output as complete"
grep -q 'Failed to transcode.*broken.jpg' "$test_tmp/failures.err" ||
  fail "folder transcoding reports failed files"
pass "folder transcoding continues after individual failures"

migration_home="$test_tmp/migration-home"
HOME="$migration_home" OMARCHY_PATH="$ROOT" bash -euo pipefail "$ROOT/migrations/1786437940.sh" >/dev/null
cmp "$ROOT/default/nautilus-python/extensions/transcode.py" \
  "$migration_home/.local/share/nautilus-python/extensions/transcode.py" >/dev/null ||
  fail "folder transcoding migration refreshes the Quattro Nautilus extension"
pass "folder transcoding migration uses the Quattro package layout"

ROOT="$ROOT" python - <<'PY'
import importlib.util
import os
import sys
import types


class GObjectBase:
    pass


class MenuProvider:
    pass


gi = types.ModuleType("gi")
gi.require_version = lambda *_: None
repository = types.ModuleType("gi.repository")
repository.GObject = types.SimpleNamespace(GObject=GObjectBase)
repository.Gio = types.SimpleNamespace(SubprocessFlags=types.SimpleNamespace(NONE=0))
repository.Nautilus = types.SimpleNamespace(MenuProvider=MenuProvider)
gi.repository = repository
sys.modules["gi"] = gi
sys.modules["gi.repository"] = repository

path = os.path.join(os.environ["ROOT"], "default/nautilus-python/extensions/transcode.py")
spec = importlib.util.spec_from_file_location("transcode", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
action = module.TranscodeAction()


class Location:
    def __init__(self, path):
        self.path = path

    def get_path(self):
        return self.path


class File:
    def __init__(self, path, directory=False, mime=""):
        self.path = path
        self.directory = directory
        self.mime = mime

    def is_directory(self):
        return self.directory

    def get_mime_type(self):
        return self.mime

    def get_location(self):
        return Location(self.path)


folder = File("/tmp/media folder", directory=True)
picture = File("/tmp/photo.jpg", mime="image/jpeg")
second_picture = File("/tmp/second photo.jpg", mime="image/jpeg")
assert action._selected_paths([folder]) == [("directory", "/tmp/media folder")]
assert action._selected_paths([folder, picture]) == []
assert action._selected_paths([picture]) == [("picture", "/tmp/photo.jpg")]

command = action._batch_command("/usr/bin/omarchy-transcode", "picture", [
    "/tmp/photo.jpg", "/tmp/second photo.jpg"
])
assert command.count("Select picture format") == 1
assert command.count("Select picture resolution") == 1
assert command.count("/usr/bin/omarchy-transcode") == 2
PY
pass "Nautilus supports folders and prompts once for multi-file batches"
