#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const utilQml = fs.readFileSync(path.join(root, 'shell/Commons/Util.qml'), 'utf8')
const mediaQml = fs.readFileSync(path.join(root, 'shell/Ui/BackgroundMedia.qml'), 'utf8')
const videoQml = fs.readFileSync(path.join(root, 'shell/Ui/BackgroundVideo.qml'), 'utf8')
const backgroundQml = fs.readFileSync(path.join(root, 'shell/plugins/background/Background.qml'), 'utf8')
const lockQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')
const themeSwitcher = fs.readFileSync(path.join(root, 'bin/omarchy-theme-switcher'), 'utf8')
const quattroUpgrade = fs.readFileSync(path.join(root, 'bin/omarchy-upgrade-to-quattro'), 'utf8')
const multimediaMigration = fs.readFileSync(path.join(root, 'migrations/1786609204.sh'), 'utf8')
const barTextColor = fs.readFileSync(path.join(root, 'bin/omarchy-bar-text-color'), 'utf8')

assert(
  /function isVideoPath\(path\)[\s\S]*\.test\(String\(path \|\| ""\)\)/.test(utilQml) &&
    !utilQml.includes('split(/[?#]/)'),
  'shared media helper identifies video paths without truncating valid local names'
)
assert(
  videoQml.includes('loops: MediaPlayer.Infinite') &&
    videoQml.includes('autoPlay: root.playbackEnabled') &&
    videoQml.includes('fillMode: VideoOutput.PreserveAspectCrop') &&
    mediaQml.includes('!video && version'),
  'background media plays aspect-cropped videos on a loop'
)
assert(
  !/^\s*import QtMultimedia/m.test(mediaQml) &&
    mediaQml.includes('source: "BackgroundVideo.qml"'),
  'the still-image path never imports QtMultimedia, so image-only sessions do not map it'
)
assert(
  /^\s*audioOutput: null$/m.test(videoQml) &&
    /^\s*activeAudioTrack: -1$/m.test(videoQml) &&
    !/^\s*Video\s*\{/m.test(videoQml) &&
    !/AudioOutput\s*\{/.test(videoQml) &&
    !/^\s*muted\s*:/m.test(videoQml),
  'wallpaper playback builds no audio output, which a muted Video convenience type would'
)
assert(
  !mediaQml.includes('mipmap'),
  'the shared image path leaves mipmapping off, as the desktop background had it'
)
assert(
  /instant \|\| !displayedBackground \|\| isVideo\(path\) \|\| isVideo\(displayedBackground\)[\s\S]*displayedBackground = finalPath/.test(backgroundQml),
  'video switches bypass the image-only reveal stack and use the durable background path'
)
assert(backgroundQml.includes('BackgroundMedia {') && lockQml.includes('BackgroundMedia {'), 'desktop and lock screen share video-capable media rendering')
assert(
  lockQml.includes('source: wallpaper.video ? null : wallpaper') &&
    lockQml.includes('visible: !wallpaper.video') &&
    lockQml.includes('visible: wallpaper.video'),
  'lock screen bypasses its image effect for video output'
)
assert(
  /obscured:\s*fullscreenActive \|\| lockActive \|\| screensaverActive/.test(backgroundQml) &&
    backgroundQml.includes('playbackEnabled: !root.obscured') &&
    backgroundQml.includes('omarchy.lock') &&
    backgroundQml.includes('omarchy.idle'),
  'desktop playback stops while locked or screensaved, not only while fullscreen'
)
assert(
  barTextColor.includes('magick "$background_path[0]"'),
  'bar colour sampling reads one frame instead of decoding a whole video'
)
assert(themeSwitcher.includes("-iname '*.mp4'") && themeSwitcher.includes('mp4 m4v mov webm mkv avi'), 'theme switcher previews video-only themes')
assert(quattroUpgrade.includes("-iname '*.mp4'"), 'Quattro upgrade can seed a video-only theme background')
assert(
  multimediaMigration.includes('omarchy-pkg-add qt6-multimedia qt6-multimedia-ffmpeg'),
  'existing Quattro installations receive video playback dependencies'
)
JS

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/backgrounds" "$test_tmp/cache"
printf 'not a real video\n' >"$test_tmp/backgrounds/sample.mp4"

cat >"$test_tmp/bin/ffmpegthumbnailer" <<'SH'
#!/bin/bash
while (( $# > 0 )); do
  case "$1" in
    -i) input=$2; shift 2 ;;
    -o) output=$2; shift 2 ;;
    *) shift ;;
  esac
done
printf 'thumbnail for %s\n' "$input" >"$output"
SH
chmod +x "$test_tmp/bin/ffmpegthumbnailer"

PATH="$test_tmp/bin:$PATH" XDG_CACHE_HOME="$test_tmp/cache" \
  "$ROOT/bin/omarchy-menu-images" --prepare-only "$test_tmp/backgrounds"

thumbnail=$(find "$test_tmp/cache/omarchy/image-selector" -maxdepth 1 -type f -name '*.jpg' -print -quit)
[[ -s $thumbnail ]] || fail "video picker generates a still thumbnail"

row=$(XDG_CACHE_HOME="$test_tmp/cache" "$ROOT/shell/plugins/image-picker/list.sh" "$test_tmp/backgrounds")
IFS=$'\t' read -r row_path row_thumbnail <<<"$row"
[[ $row_path == "$test_tmp/backgrounds/sample.mp4" && $row_thumbnail == "$thumbnail" ]] || \
  fail "image picker lists videos with their cached thumbnail" "$row"

grep -qx 'qt6-multimedia' "$ROOT/install/omarchy-base.packages" || fail "Qt Multimedia runtime is a base package"
grep -qx 'qt6-multimedia-ffmpeg' "$ROOT/install/omarchy-base.packages" || fail "Qt Multimedia FFmpeg backend is a base package"

pass "video picker generates and reuses still thumbnails"
pass "Qt Multimedia playback dependencies are declared"
