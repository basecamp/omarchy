#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
notification_args="$tmpdir/notification-args"
mkdir -p "$mock_bin" "$tmpdir/home"

cat >"$mock_bin/pkill" <<'EOF'
#!/bin/bash
exit 1
EOF

cat >"$mock_bin/hyprctl" <<'EOF'
#!/bin/bash
if [[ ${1:-} == "getoption" ]]; then
  printf '{"int":0}\n'
fi
EOF

cat >"$mock_bin/omarchy-capture-region" <<'EOF'
#!/bin/bash
printf '\n0,0 10x10\n'
EOF

cat >"$mock_bin/grim" <<'EOF'
#!/bin/bash
output=${@: -1}
printf 'fake png' >"$output"
EOF

cat >"$mock_bin/wl-copy" <<'EOF'
#!/bin/bash
cat >/dev/null
EOF

cat >"$mock_bin/omarchy-notification-send" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_NOTIFICATION_ARGS"
EOF

chmod +x "$mock_bin"/*

output=$(HOME="$tmpdir/home" OMARCHY_TEST_NOTIFICATION_ARGS="$notification_args" \
  PATH="$mock_bin:$ROOT/bin:/usr/bin" OMARCHY_SCREENSHOT_EDITOR=test-editor \
  "$ROOT/bin/omarchy-capture-screenshot")

[[ -f $output ]] || fail "screenshot creates the file announced on stdout" "$output"
mapfile -d '' -t args <"$notification_args"

image_path=
drag_path=
editor=
editor_path=
for ((i = 0; i < ${#args[@]}; i++)); do
  case ${args[i]} in
  --image) image_path=${args[i + 1]:-} ;;
  --drag-file) drag_path=${args[i + 1]:-} ;;
  --exec)
    editor=${args[i + 1]:-}
    editor_path=${args[i + 2]:-}
    ;;
  esac
done

[[ $image_path == "$output" ]] || fail "screenshot uses the saved file as the notification image" "$image_path"
[[ $drag_path == "$output" ]] || fail "screenshot offers the saved file for notification dragging" "$drag_path"
[[ $editor == "test-editor" && $editor_path == "$output" ]] || fail "screenshot keeps click-to-edit alongside dragging"
pass "screenshots notify with one file for the thumbnail, drag payload, and editor action"
