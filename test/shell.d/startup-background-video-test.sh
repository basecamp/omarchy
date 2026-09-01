#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const startup = requireFromRoot('shell/plugins/background/StartupBackgroundModel.js')

assertDeepEqual(
  startup.assetsForBackground('/themes/current/backgrounds/city.webp'),
  {
    videoPath: '/themes/current/backgrounds/startup/city/video.mp4',
    firstFramePath: '/themes/current/backgrounds/startup/city/first-frame.webp'
  },
  'startup media is paired with the selected WebP background'
)
assertDeepEqual(
  startup.assetsForBackground('/themes/current/backgrounds/city.night.jpeg'),
  {
    videoPath: '/themes/current/backgrounds/startup/city.night/video.mp4',
    firstFramePath: '/themes/current/backgrounds/startup/city.night/first-frame.webp'
  },
  'startup media keeps dots in a background name and ignores only its final extension'
)
assertDeepEqual(
  startup.assetsForBackground('/themes/current/backgrounds/city'),
  { videoPath: '', firstFramePath: '' },
  'a path without an image extension cannot claim startup media'
)
assertDeepEqual(
  startup.assetsForBackground('relative/city.webp'),
  { videoPath: '', firstFramePath: '' },
  'startup media requires the resolved absolute background path'
)

assertEqual(
  startup.sessionClaimPath('/run/user/1000/', 'abc_123-4.5'),
  '/run/user/1000/omarchy-startup-background-video-abc_123-4.5',
  'startup playback derives a claim unique to the Hyprland session'
)
assertEqual(startup.sessionClaimPath('', 'abc'), '', 'startup playback fails closed without a private runtime directory')
assertEqual(startup.sessionClaimPath('/run/user/1000', ''), '', 'startup playback fails closed without a compositor session identity')
assertEqual(startup.sessionClaimPath('/run/user/1000', '../other'), '', 'startup playback rejects a session identity containing path syntax')

const backgroundQml = fs.readFileSync(path.join(root, 'shell/plugins/background/Background.qml'), 'utf8')
const startupQml = fs.readFileSync(path.join(root, 'shell/plugins/background/StartupBackgroundVideo.qml'), 'utf8')
const videoQml = fs.readFileSync(path.join(root, 'shell/Ui/BackgroundVideo.qml'), 'utf8')
const shellQml = fs.readFileSync(path.join(root, 'shell/shell.qml'), 'utf8')
const uiModule = fs.readFileSync(path.join(root, 'shell/Ui/qmldir'), 'utf8')
const themeSet = fs.readFileSync(path.join(root, 'bin/omarchy-theme-set'), 'utf8')
const migration = fs.readFileSync(path.join(root, 'migrations/1788137913.sh'), 'utf8')

assert(
  !/^\s*import QtMultimedia/m.test(backgroundQml) &&
    !/^\s*import QtMultimedia/m.test(startupQml) &&
    /^\s*import QtMultimedia/m.test(videoQml) &&
    startupQml.includes('source: Qt.resolvedUrl("../../Ui/BackgroundVideo.qml")'),
  'Qt Multimedia is loaded by URL only when a startup video is active'
)
assert(
  /^\s*audioOutput: null$/m.test(videoQml) &&
    !/^\s*Video\s*\{/m.test(videoQml) &&
    videoQml.includes('fillMode: VideoOutput.PreserveAspectCrop'),
  'startup playback decodes no audio and aspect-crops native video output'
)
assert(
  videoQml.includes('endOfStreamPolicy: VideoOutput.KeepLastFrame') &&
    videoQml.includes('function onVideoFrameChanged()') &&
    startupQml.includes('onVideoReadyChanged:'),
  'startup playback stays hidden until a decoded frame and retains its final frame for handoff'
)
assert(
  videoQml.includes('root.loop ? MediaPlayer.Infinite : MediaPlayer.Once') &&
    /property: "loop"[\s\S]*?value: false/.test(startupQml),
  'the reusable player loops by default while startup playback explicitly runs once'
)
assert(
  startupQml.includes('id: decodeTimeout') &&
    startupQml.includes('id: playbackTimeout') &&
    startupQml.includes('id: finishFade'),
  'decode, playback, and static handoff are all time bounded'
)
assert(
  backgroundQml.includes('Quickshell.env("XDG_RUNTIME_DIR")') &&
    backgroundQml.includes('Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")') &&
    backgroundQml.includes('command: ["mkdir", root.startupSessionClaimPath]'),
  'the background service atomically claims playback in the private compositor session'
)
assert(
  backgroundQml.includes('omarchy.lock') &&
    backgroundQml.includes('omarchy.idle') &&
    /onSessionObscuredChanged: if \(sessionObscured && startupPrepared\) cancelStartup\(\)/.test(backgroundQml) &&
    /obscured: panel\.fullscreenHere/.test(backgroundQml),
  'startup playback ends when globally hidden and only the covered output ends for fullscreen'
)
assert(
  backgroundQml.includes('root.currentBackground !== root.startupBackgroundPath') &&
    backgroundQml.includes('finalPath !== startupBackgroundPath'),
  'a background change cannot start or retain stale startup media'
)
assert(
  shellQml.includes('readonly property var services: _services'),
  'service lookup becomes reactive when background loads before lock or idle'
)
assert(/^BackgroundVideo 1\.0 BackgroundVideo\.qml$/m.test(uiModule), 'the reusable player is exported from the shared UI module')
assert(
  /find -L [\s\S]* -maxdepth 1 -type f/.test(themeSet) &&
    /stage_installed_dir "\$entry" "\$NEXT_THEME_PATH\/\$name"/.test(themeSet),
  'nested startup media is staged with its theme but remains outside the wallpaper picker'
)
assert(
  migration.includes('omarchy-pkg-add qt6-multimedia qt6-multimedia-ffmpeg'),
  'existing installations receive both native video playback packages'
)
JS

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"

cat >"$test_tmp/bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$PACKAGE_LOG"
SH
chmod +x "$test_tmp/bin/omarchy-pkg-add"

PACKAGE_LOG="$test_tmp/packages" PATH="$test_tmp/bin:$PATH" \
  bash -euo pipefail "$ROOT/migrations/1788137913.sh" >/dev/null

grep -qx 'qt6-multimedia qt6-multimedia-ffmpeg' "$test_tmp/packages" || fail "startup video migration installs both playback packages"
grep -qx 'qt6-multimedia' "$ROOT/install/omarchy-base.packages" || fail "Qt Multimedia runtime is a base package"
grep -qx 'qt6-multimedia-ffmpeg' "$ROOT/install/omarchy-base.packages" || fail "Qt Multimedia FFmpeg backend is a base package"
[[ $(stat -c %a "$ROOT/migrations/1788137913.sh") == "644" ]] || fail "startup video migration is non-executable"

pass "startup video migration installs both playback packages"
pass "fresh installs declare both startup video playback packages"
pass "startup video migration uses the required file mode"
