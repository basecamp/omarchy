#!/bin/bash

set -euo pipefail

# A theme's startup sound may have arrived through `omarchy theme install`, so
# omarchy-theme-startup-sound treats it as data: it plays only a regular file
# with an audio extension that really is audio and fits under the size cap, and
# it hands the file to pw-play rather than a player that runs scripts.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command file

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
theme="$home/.local/state/omarchy/current/theme"
stubs="$test_tmp/bin"
log="$test_tmp/pw-play.log"
mkdir -p "$theme" "$stubs"

cat >"$stubs/pw-play" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$PW_PLAY_LOG"
STUB

cat >"$stubs/wpctl" <<'STUB'
#!/bin/bash
exit 0
STUB

chmod +x "$stubs"/*

# The smallest thing libmagic calls WAVE audio: a RIFF header with no samples.
write_wav() {
  printf 'RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x02\x00\x80\xbb\x00\x00\x00\xee\x02\x00\x04\x00\x10\x00data\x00\x00\x00\x00' >"$1"
}

play() {
  : >"$log"
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stubs:$ROOT/bin:$PATH" PW_PLAY_LOG="$log" \
    bash "$ROOT/bin/omarchy-theme-startup-sound" 2>"$test_tmp/stderr"
}

played() {
  [[ -s $log ]]
}

reset_theme() {
  rm -rf "$theme"
  mkdir -p "$theme"
}

# No sound in the theme: nothing plays and nothing fails.
play || fail "omarchy-theme-startup-sound succeeds when the theme has no sound"
played && fail "nothing is played when the theme has no startup sound"
pass "a theme without a startup sound logs in quietly"

# A real sound file is handed to pw-play by path.
write_wav "$theme/startup.wav"
play || fail "omarchy-theme-startup-sound plays a theme's startup.wav"
grep -qx -- "$theme/startup.wav" "$log" || fail "pw-play receives the staged sound path" "$(cat "$log")"
pass "a theme's startup sound is played with pw-play"

# The startup-sound-off toggle wins over the theme.
mkdir -p "$home/.local/state/omarchy/toggles"
touch "$home/.local/state/omarchy/toggles/startup-sound-off"
play || fail "omarchy-theme-startup-sound succeeds when startup sounds are off"
played && fail "nothing is played while startup-sound-off is set"
rm "$home/.local/state/omarchy/toggles/startup-sound-off"
pass "the startup-sound-off toggle silences every theme"

# Only an audio extension is looked for, so a script named startup.sh is never
# opened at all.
reset_theme
printf '#!/bin/bash\necho payload\n' >"$theme/startup.sh"
play || fail "omarchy-theme-startup-sound ignores a file without an audio extension"
played && fail "a startup.sh is not played"
pass "a startup sound needs an audio extension"

# An audio extension on something that is not audio is refused by content.
reset_theme
printf '#!/bin/bash\necho payload\n' >"$theme/startup.wav"
play && fail "omarchy-theme-startup-sound refuses a startup.wav that is a shell script"
played && fail "a shell script named startup.wav is not played"
grep -q 'not audio' "$test_tmp/stderr" || fail "the refusal names the detected type" "$(cat "$test_tmp/stderr")"
pass "a startup sound has to be audio by content, not just by name"

# A symlink is refused even though staging should already have dropped it: the
# staged theme is user-writable state.
reset_theme
write_wav "$test_tmp/elsewhere.wav"
ln -s "$test_tmp/elsewhere.wav" "$theme/startup.wav"
play || fail "omarchy-theme-startup-sound exits cleanly on a symlinked sound"
played && fail "a symlinked startup sound is not played"
grep -q 'symlink' "$test_tmp/stderr" || fail "the refusal names the symlink" "$(cat "$test_tmp/stderr")"
pass "a symlinked startup sound is not followed"

# A sound over the size cap is refused before its contents are inspected.
reset_theme
write_wav "$theme/startup.wav"
truncate -s 11M "$theme/startup.wav"
play && fail "omarchy-theme-startup-sound refuses an oversized sound"
played && fail "an oversized startup sound is not played"
grep -q 'larger than' "$test_tmp/stderr" || fail "the refusal names the size cap" "$(cat "$test_tmp/stderr")"
pass "a startup sound over the size cap is refused"

# Every accepted extension is found, and only the first one plays.
for extension in flac ogg oga opus mp3; do
  reset_theme
  write_wav "$theme/startup.$extension"
  play || fail "omarchy-theme-startup-sound plays startup.$extension"
  grep -qx -- "$theme/startup.$extension" "$log" || fail "pw-play receives startup.$extension" "$(cat "$log")"
done
pass "every accepted audio extension is played"

reset_theme
write_wav "$theme/startup.wav"
write_wav "$theme/startup.ogg"
play || fail "omarchy-theme-startup-sound plays a theme with two sounds"
(( $(wc -l <"$log") == 1 )) || fail "only one startup sound plays" "$(cat "$log")"
pass "a theme with several startup sounds plays one"

# Without a default sink there is nothing to play to, and login must not hang.
cat >"$stubs/wpctl" <<'STUB'
#!/bin/bash
exit 1
STUB
reset_theme
write_wav "$theme/startup.wav"
start=$SECONDS
play || fail "omarchy-theme-startup-sound exits cleanly without an audio sink"
played && fail "nothing is played without an audio sink"
(( SECONDS - start <= 12 )) || fail "the wait for an audio sink gives up in time"
pass "a session without an audio sink gives up quietly"
