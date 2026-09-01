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
const menuImages = fs.readFileSync(path.join(root, 'bin/omarchy-menu-images'), 'utf8')
const lockView = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')
const lockService = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')
const bootIntro = fs.readFileSync(path.join(root, 'bin/omarchy-theme-bg-boot-intro'), 'utf8')
const themeSet = fs.readFileSync(path.join(root, 'bin/omarchy-theme-set'), 'utf8')

assert(
  /function isVideoPath\(path\)[\s\S]*\.test\(String\(path \|\| ""\)\)/.test(utilQml) &&
    !utilQml.includes('split(/[?#]/)'),
  'shared media helper identifies video paths without truncating valid local names'
)
assert(
  videoQml.includes('loops: root.loop ? MediaPlayer.Infinite : 1') &&
    videoQml.includes('autoPlay: root.playbackEnabled') &&
    videoQml.includes('fillMode: VideoOutput.PreserveAspectCrop') &&
    mediaQml.includes('!video && version'),
  'background media plays aspect-cropped videos on a loop'
)
assert(
  videoQml.includes('mediaStatus === MediaPlayer.EndOfMedia') &&
    mediaQml.includes('property bool loop: true') &&
    backgroundQml.includes('command: ["omarchy-theme-bg-boot-intro"]') &&
    backgroundQml.includes('path: root.bootIntroActive ? root.bootIntroPath : ""') &&
    backgroundQml.includes('loop: false') &&
    backgroundQml.includes('onFinished: root.finishBootIntro()') &&
    bootIntro.includes('background-intro.boot-id'),
  'a matching theme intro plays once per boot and reveals the loaded still at end of media'
)
assert(
  !/^\s*import QtMultimedia/m.test(mediaQml) &&
    mediaQml.includes('source: "BackgroundVideo.qml"') &&
    mediaQml.includes('source: Util.isVideoPath(root.path) ? "" : root.mediaUrl'),
  'the still-image path never imports QtMultimedia, so image-only sessions do not map it'
)
assert(
  /^\s*audioOutput: null$/m.test(videoQml) &&
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
  /sessionObscured:\s*lockActive \|\| screensaverActive/.test(backgroundQml) &&
    backgroundQml.includes('playbackEnabled: !root.sessionObscured && !panel.fullscreenHere') &&
    backgroundQml.includes('omarchy.lock') &&
    backgroundQml.includes('omarchy.idle'),
  'desktop playback stops while locked or screensaved, not only while fullscreen'
)
assert(
  /fullscreenHere:[\s\S]*?Hyprland\.focusedMonitor\.name \|\| ""\) === String\(modelData\.name/.test(backgroundQml),
  'a fullscreen window pauses only the output it covers, not every wallpaper'
)
assert(
  barTextColor.includes('magick "$background_path[0]"'),
  'bar colour sampling reads one frame instead of decoding a whole video'
)
assert(
  menuImages.includes('pending_video_file') && /video_jobs=\$\(\( \$\(nproc\) \/ 4 \)\)/.test(menuImages),
  'video thumbnails fan out narrower than single-threaded vips jobs'
)
assert(
  themeSwitcher.includes('fast_signature="v2"'),
  'the theme preview cache rebuilds after preview discovery learned about video'
)
assert(
  /lazy_thumbnails == true && \$cache_only != true \]\] && ! is_video_path/.test(menuImages),
  'a video never stands in as its own lazy thumbnail, so the fan out cap always applies'
)
assert(
  /thumbnail_command=\(timeout -k \d+ \d+ ffmpegthumbnailer/.test(menuImages),
  'a stalled video cannot hold the picker shut, because its generator is time bounded'
)
assert(
  themeSet.includes('choose_staged_theme_background') &&
    themeSet.includes('background_transition_uses_snapshots') &&
    themeSet.includes('BACKGROUND_TRANSITION_SNAPSHOTS=false') &&
    /if \[\[ \$BACKGROUND_TRANSITION_SNAPSHOTS == "true" \]\]/.test(themeSet) &&
    /if \[\[ -z \$CHOSEN_THEME_BACKGROUND \|\| ! -f \$CHOSEN_THEME_BACKGROUND \]\]/.test(themeSet),
  'theme changes disable both transition snapshots whenever either side is a video'
)
assert(
  /function onScreensChanged\(\) \{[\s\S]*?root\.displaysBlank = false/.test(lockService),
  'a display coming back gives up the blank state instead of freezing a visible wallpaper'
)
assert(
  lockView.includes('playbackEnabled: root.loadBackground && !root.displaysBlank') &&
    /displaysBlank: root\.displaysBlank/.test(lockService) &&
    /function runBlank\(\) \{\s*\n\s*root\.displaysBlank = true/.test(lockService) &&
    /function runWake\(\) \{\s*\n\s*root\.displaysBlank = false/.test(lockService),
  'the lock screen stops its own playback once the displays go dark'
)
assert(
  themeSwitcher.includes("-iname '*.mp4'") &&
    themeSwitcher.includes('mp4 m4v mov webm mkv avi') &&
    themeSwitcher.includes('preview.mp4'),
  'theme switcher previews video-only themes, named preview files included'
)
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

source <(awk '
  /^(is_video_path|snapshot_background_path|background_transition_uses_snapshots|choose_theme_background|choose_staged_theme_background|set_theme_background)\(\) \{/ { copying=1 }
  copying { print }
  copying && /^}$/ { copying=0 }
' "$ROOT/bin/omarchy-theme-set")

transition_home="$test_tmp/transition-home"
CURRENT_THEME_PATH="$transition_home/.local/state/omarchy/current/theme"
NEXT_THEME_PATH="$transition_home/.local/state/omarchy/current/next-theme"
CURRENT_BACKGROUND_LINK="$transition_home/.local/state/omarchy/current/background"
BACKGROUND_TRANSITION_CACHE="$transition_home/.cache/omarchy/background-transitions"
THEME_NAME="video-test"
HOME="$transition_home"
mkdir -p "$CURRENT_THEME_PATH/backgrounds" "$NEXT_THEME_PATH/backgrounds" "$HOME/.config/omarchy/backgrounds/$THEME_NAME"
printf 'old image\n' >"$CURRENT_THEME_PATH/backgrounds/old.png"
printf 'old image staged\n' >"$NEXT_THEME_PATH/backgrounds/old.png"
printf 'new video\n' >"$NEXT_THEME_PATH/backgrounds/new.mp4"
ln -s "$CURRENT_THEME_PATH/backgrounds/old.png" "$CURRENT_BACKGROUND_LINK"

choose_staged_theme_background || fail "staged video background is selected before the theme swap"
expected_staged_background="$CURRENT_THEME_PATH/backgrounds/new.mp4"
[[ $CHOSEN_THEME_BACKGROUND == $expected_staged_background ]] || \
  fail "staged background resolves to its durable post-swap path" "$CHOSEN_THEME_BACKGROUND"
if background_transition_uses_snapshots "$CHOSEN_THEME_BACKGROUND"; then
  fail "image to video theme transitions skip snapshots"
fi
background_transition_uses_snapshots "$CURRENT_THEME_PATH/backgrounds/new.png" || \
  fail "image to image theme transitions retain snapshots"

rm "$CURRENT_BACKGROUND_LINK"
printf 'old video\n' >"$CURRENT_THEME_PATH/backgrounds/old.mp4"
ln -s "$CURRENT_THEME_PATH/backgrounds/old.mp4" "$CURRENT_BACKGROUND_LINK"
if background_transition_uses_snapshots "$CURRENT_THEME_PATH/backgrounds/new.png"; then
  fail "video to image theme transitions skip snapshots"
fi

video_snapshot=$(snapshot_background_path "$CURRENT_THEME_PATH/backgrounds/old.mp4" "video")
[[ -z $video_snapshot && ! -e $BACKGROUND_TRANSITION_CACHE ]] || fail "video files are never snapshotted"

CHOSEN_THEME_BACKGROUND="$transition_home/disappeared.mp4"
BACKGROUND_TRANSITION_SNAPSHOTS=false
OLD_BACKGROUND_SNAPSHOT=""
colors_payload=""
shell_payload=""
shell_ipc() { :; }
set_theme_background
[[ -f $CHOSEN_THEME_BACKGROUND && $(readlink "$CURRENT_BACKGROUND_LINK") == "$CHOSEN_THEME_BACKGROUND" ]] || \
  fail "theme changes recover when a preselected background disappears" "$CHOSEN_THEME_BACKGROUND"

pass "theme transitions skip snapshots whenever either side is a video"
pass "theme changes recover from a missing preselected background"

intro_home="$test_tmp/intro-home"
intro_state="$intro_home/.local/state/omarchy/current"
mkdir -p "$intro_state/theme/backgrounds" "$intro_state/theme/intros"
printf 'still\n' >"$intro_state/theme/backgrounds/0-winding-road.webp"
printf 'video\n' >"$intro_state/theme/intros/0-winding-road.mp4"
ln -s "$intro_state/theme/backgrounds/0-winding-road.webp" "$intro_state/background"

intro=$(HOME="$intro_home" OMARCHY_BOOT_ID=video-test-boot "$ROOT/bin/omarchy-theme-bg-boot-intro")
[[ $intro == "$intro_state/theme/intros/0-winding-road.mp4" ]] || \
  fail "boot intro resolves by the selected background stem" "$intro"

second_intro=$(HOME="$intro_home" OMARCHY_BOOT_ID=video-test-boot "$ROOT/bin/omarchy-theme-bg-boot-intro")
[[ -z $second_intro ]] || fail "boot intro runs once for a boot id" "$second_intro"

pass "boot intro resolves the selected still once per boot"

migration="$ROOT/migrations/1788281348.sh"
migration_home="$test_tmp/migration-home"
migration_bin="$test_tmp/migration-bin"
migration_calls="$test_tmp/migration-calls"
mkdir -p "$migration_home/.local/state/omarchy/current" "$migration_bin"

cat >"$migration_bin/omarchy-theme-refresh" <<'SH'
#!/bin/bash
printf 'refresh\n' >>"$MIGRATION_CALLS"
SH
chmod +x "$migration_bin/omarchy-theme-refresh"

printf 'tokyo-night\n' >"$migration_home/.local/state/omarchy/current/theme.name"
HOME="$migration_home" PATH="$migration_bin:$PATH" MIGRATION_CALLS="$migration_calls" \
  bash -euo pipefail "$migration" >/dev/null
[[ $(<"$migration_calls") == "refresh" ]] || fail "boot intro migration refreshes an active Tokyo Night theme"

: >"$migration_calls"
printf 'catppuccin\n' >"$migration_home/.local/state/omarchy/current/theme.name"
HOME="$migration_home" PATH="$migration_bin:$PATH" MIGRATION_CALLS="$migration_calls" \
  bash -euo pipefail "$migration" >/dev/null
[[ ! -s $migration_calls ]] || fail "boot intro migration leaves another active theme alone"

rm "$migration_home/.local/state/omarchy/current/theme.name"
HOME="$migration_home" PATH="$migration_bin:$PATH" MIGRATION_CALLS="$migration_calls" \
  bash -euo pipefail "$migration" >/dev/null
[[ ! -s $migration_calls ]] || fail "boot intro migration tolerates missing theme state"

pass "boot intro migration stages assets only for an active Tokyo Night theme"
