#!/bin/bash

set -euo pipefail

# A theme's startup sound may have arrived through `omarchy theme install`.
# Only a canonical PCM WAV is accepted, and pw-play receives raw samples so its
# native container decoders never parse the untrusted file.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
theme="$home/.local/state/omarchy/current/theme"
stubs="$test_tmp/bin"
log="$test_tmp/pw-play.log"
timeout_log="$test_tmp/timeout.log"
pid_file="$test_tmp/pw-play.pid"
notification_log="$test_tmp/notification.log"
runtime="$test_tmp/runtime"
mkdir -p "$theme" "$stubs" "$runtime"

write_pw_play_stub() {
  cat >"$stubs/pw-play" <<'STUB'
#!/bin/bash
printf 'args=%s\n' "$*" >>"$PW_PLAY_LOG"

if [[ -n ${REPLACE_SOUND_WITH:-} ]]; then
  cp -- "$REPLACE_SOUND_WITH" "$ORIGINAL_SOUND"
fi

raw_sound=${!#}
printf 'payload=%s\n' "$(base64 -w 0 -- "$raw_sound")" >>"$PW_PLAY_LOG"
STUB
  chmod +x "$stubs/pw-play"
}

write_pw_play_stub

cat >"$stubs/wpctl" <<'STUB'
#!/bin/bash
exit 0
STUB

cat >"$stubs/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFICATION_LOG"
STUB

# Keep ordinary calls unchanged, but shorten the playback deadline so a player
# that ignores TERM can be exercised without adding 16 seconds to this test.
cat >"$stubs/timeout" <<'STUB'
#!/bin/bash
original=("$@")
kill_after=""

if [[ ${1:-} == --kill-after=* ]]; then
  kill_after=$1
  shift
fi

duration=${1:-}
shift || true

printf '%s\n' "${original[*]}" >>"$TIMEOUT_LOG"

if [[ ${1:-} == "pw-play" ]]; then
  [[ -n $kill_after ]] || exit 98
  exec /usr/bin/timeout --kill-after=0.1s 0.2s "$@"
else
  exec /usr/bin/timeout "${original[@]}"
fi
STUB

chmod +x "$stubs/wpctl" "$stubs/timeout" "$stubs/omarchy-notification-send"

# Canonical 48-byte stereo WAV: one 48 kHz, signed 16-bit PCM frame whose raw
# sample bytes are 01 02 03 04.
write_wav() {
  printf 'RIFF\x28\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x02\x00\x80\xbb\x00\x00\x00\xee\x02\x00\x04\x00\x10\x00data\x04\x00\x00\x00\x01\x02\x03\x04' >"$1"
}

write_other_wav() {
  printf 'RIFF\x28\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x02\x00\x80\xbb\x00\x00\x00\xee\x02\x00\x04\x00\x10\x00data\x04\x00\x00\x00\x09\x0a\x0b\x0c' >"$1"
}

write_mono_wav() {
  printf 'RIFF\x26\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x80\xbb\x00\x00\x00\x77\x01\x00\x02\x00\x10\x00data\x02\x00\x00\x00\x05\x06' >"$1"
}

enable_startup_sound() {
  mkdir -p "$home/.local/state/omarchy/toggles"
  touch "$home/.local/state/omarchy/toggles/startup-sound-enabled"
}

play() {
  : >"$log"
  : >"$timeout_log"
  HOME="$home" OMARCHY_PATH="$ROOT" XDG_RUNTIME_DIR="$runtime" PATH="$stubs:$ROOT/bin:$PATH" \
    PW_PLAY_LOG="$log" TIMEOUT_LOG="$timeout_log" NOTIFICATION_LOG="$notification_log" \
    REPLACE_SOUND_WITH="${REPLACE_SOUND_WITH:-}" ORIGINAL_SOUND="$theme/startup.wav" \
    bash "$ROOT/bin/omarchy-theme-startup-sound" 2>"$test_tmp/stderr"
}

played() {
  grep -q '^args=' "$log"
}

reset_theme() {
  rm -rf "$theme"
  mkdir -p "$theme"
}

# Sounds are opt-in because selecting a visual theme should not make noise by
# default, especially when that theme came from a stranger's repository.
write_wav "$theme/startup.wav"
play || fail "omarchy-theme-startup-sound succeeds while startup sounds are disabled"
played && fail "nothing is played before startup sounds are explicitly enabled"
[[ ! -s $timeout_log ]] || fail "disabled startup sounds do not probe or copy anything"
pass "theme startup sounds are disabled by default"

: >"$notification_log"
HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stubs:$ROOT/bin:$PATH" NOTIFICATION_LOG="$notification_log" \
  bash "$ROOT/bin/omarchy-toggle-startup-sound"
[[ -f $home/.local/state/omarchy/toggles/startup-sound-enabled ]] || fail "the startup sound toggle creates the opt-in flag"
grep -q 'Startup sound enabled' "$notification_log" || fail "enabling startup sounds is reported"

HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stubs:$ROOT/bin:$PATH" NOTIFICATION_LOG="$notification_log" \
  bash "$ROOT/bin/omarchy-toggle-startup-sound"
[[ ! -f $home/.local/state/omarchy/toggles/startup-sound-enabled ]] || fail "the startup sound toggle removes the opt-in flag"
grep -q 'Startup sound disabled' "$notification_log" || fail "disabling startup sounds is reported"
pass "the startup sound toggle controls the positive opt-in flag"

enable_startup_sound
play || fail "omarchy-theme-startup-sound plays an enabled canonical startup.wav" "$(cat "$test_tmp/stderr")"
grep -q '^args=--raw --format=s16 --rate=48000 --channels=2 --volume=0.25 ' "$log" ||
  fail "pw-play receives fixed raw PCM arguments" "$(cat "$log")"
grep -qx 'payload=AQIDBA==' "$log" || fail "pw-play receives samples without the WAV container" "$(cat "$log")"
grep -q '^--kill-after=1s 17 pw-play ' "$timeout_log" ||
  fail "playback has a hard kill deadline" "$(cat "$timeout_log")"
grep -q 'dd .*iflag=nofollow,count_bytes' "$timeout_log" ||
  fail "the bounded snapshot refuses a final symlink" "$(cat "$timeout_log")"
pass "a canonical PCM WAV is played as bounded raw samples"

# Mono is supported without asking libsndfile to discover its channel map.
reset_theme
write_mono_wav "$theme/startup.wav"
play || fail "omarchy-theme-startup-sound plays canonical mono PCM"
grep -q -- '--channels=1 --volume=0.25' "$log" || fail "mono metadata is passed explicitly" "$(cat "$log")"
grep -qx 'payload=BQY=' "$log" || fail "mono payload reaches raw playback" "$(cat "$log")"
pass "canonical mono PCM is played without container decoding"

# No sound in the theme is a quiet success.
reset_theme
play || fail "omarchy-theme-startup-sound succeeds when the theme has no sound"
played && fail "nothing is played when the theme has no startup sound"
pass "a theme without a startup sound logs in quietly"

# Other extensions are never opened, even when their contents are WAV bytes.
write_wav "$theme/startup.mp3"
play || fail "omarchy-theme-startup-sound ignores compressed startup sound formats"
played && fail "a startup.mp3 is not sent to the player"
pass "only startup.wav is considered"

# A WAV name on non-audio content is rejected by the exact header parser.
reset_theme
printf '#!/bin/bash\necho payload\n' >"$theme/startup.wav"
play && fail "omarchy-theme-startup-sound refuses a shell script named startup.wav"
played && fail "a shell script named startup.wav is not played"
grep -q 'canonical 16-bit PCM WAV' "$test_tmp/stderr" ||
  fail "the refusal names the accepted format" "$(cat "$test_tmp/stderr")"
pass "a startup sound must match the canonical WAV layout"

# The previous MIME gate accepted any audio container under a .wav name.
reset_theme
printf 'FORM\x00\x00\x00\x04AIFF' >"$theme/startup.wav"
play && fail "omarchy-theme-startup-sound refuses AIFF content named startup.wav"
played && fail "mislabeled AIFF is not played"
pass "an audio MIME type cannot bypass the WAV format restriction"

# This 1,024-channel WAVE_FORMAT_EXTENSIBLE file triggered PipeWire's
# pre-validation channel-map overflow when handed to pw-play as a container.
reset_theme
printf %s 'UklGRjwAAABXQVZFZm10ICgAAAD+/wAEgLsAAAAA3AUACBAAFgAQAAEAAAABAAAAAAAQAIAAAKoAOJtxZGF0YQAAAAA=' |
  base64 -d >"$theme/startup.wav"
play && fail "omarchy-theme-startup-sound refuses the high-channel exploit fixture"
played && fail "the high-channel exploit fixture never reaches pw-play"
grep -q 'canonical 16-bit PCM WAV' "$test_tmp/stderr" ||
  fail "the exploit fixture is rejected as non-canonical" "$(cat "$test_tmp/stderr")"
pass "the high-channel decoder exploit is rejected before pw-play"

# This malformed RIFF file loops forever inside libsndfile 1.2.2. The exact
# layout check rejects it without invoking any container parser.
reset_theme
printf %s 'UklGRiEAAABXQVZFZm10IBAAAAABAAEAAABXQSAAVkYqZm1SSU5GT/9gACsA//////////////////////////f//////0ZPUk0AAFdSQUlGRqOt3L5NSU1NPgD///+x////////////////////////////////N/+8Pv81/4gAAF0AAAAAAP////8AAEABAEYA////TwBGKmZtUg==' |
  base64 -d >"$theme/startup.wav"
play && fail "omarchy-theme-startup-sound refuses the libsndfile hang fixture"
played && fail "the libsndfile hang fixture never reaches pw-play"
grep -q 'canonical 16-bit PCM WAV' "$test_tmp/stderr" ||
  fail "the hang fixture is rejected as non-canonical" "$(cat "$test_tmp/stderr")"
pass "the native decoder hang fixture is rejected before pw-play"

# A symlink is refused even though theme staging should already have dropped it.
reset_theme
write_wav "$test_tmp/elsewhere.wav"
ln -s "$test_tmp/elsewhere.wav" "$theme/startup.wav"
play || fail "omarchy-theme-startup-sound exits cleanly on a symlinked sound"
played && fail "a symlinked startup sound is not played"
grep -q 'symlink' "$test_tmp/stderr" || fail "the refusal names the symlink" "$(cat "$test_tmp/stderr")"
pass "a symlinked startup sound is not followed"

# Copying stops one byte beyond the cap, so an arbitrarily large source cannot
# consume unbounded temporary storage before it is rejected.
reset_theme
write_wav "$theme/startup.wav"
truncate -s 11M "$theme/startup.wav"
play && fail "omarchy-theme-startup-sound refuses an oversized sound"
played && fail "an oversized startup sound is not played"
grep -q 'larger than' "$test_tmp/stderr" || fail "the refusal names the size cap" "$(cat "$test_tmp/stderr")"
pass "a startup sound over the size cap is refused"

# A structurally valid 16-second file is rejected before playback. Its sparse
# sample body keeps the fixture cheap.
reset_theme
printf 'RIFF\x24\x11\x2b\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x02\x00\x44\xac\x00\x00\x10\xb1\x02\x00\x04\x00\x10\x00data\x00\x11\x2b\x00' >"$theme/startup.wav"
truncate -s 2822444 "$theme/startup.wav"
play && fail "omarchy-theme-startup-sound refuses audio longer than 15 seconds"
played && fail "overlong audio is not played"
grep -q 'longer than 15 seconds' "$test_tmp/stderr" || fail "the refusal names the duration cap" "$(cat "$test_tmp/stderr")"
pass "the WAV header cannot claim more than 15 seconds of samples"

# Mutating the staged pathname once pw-play starts cannot change the private raw
# file that was validated and passed to it.
reset_theme
write_wav "$theme/startup.wav"
write_other_wav "$test_tmp/replacement.wav"
REPLACE_SOUND_WITH="$test_tmp/replacement.wav" play || fail "a concurrent theme change does not disrupt playback"
grep -qx 'payload=AQIDBA==' "$log" || fail "the player consumes the validated snapshot" "$(cat "$log")"
cmp -s "$theme/startup.wav" "$test_tmp/replacement.wav" || fail "the race fixture replaced the staged pathname"
unset REPLACE_SOUND_WITH
pass "playback uses the validated snapshot rather than reopening the theme path"

# A player stuck in native code and ignoring TERM must still die shortly after
# the playback timeout. The timeout stub above compresses 17 seconds to 0.2.
cat >"$stubs/pw-play" <<'STUB'
#!/bin/bash
printf '%s\n' "$$" >"$PW_PLAY_PID_FILE"
trap '' TERM
while :; do :; done
STUB
chmod +x "$stubs/pw-play"

reset_theme
write_wav "$theme/startup.wav"
start=$SECONDS
PW_PLAY_PID_FILE="$pid_file" play && fail "a killed player reports a successful playback"
(( SECONDS - start < 3 )) || fail "the hard kill deadline returns promptly"
[[ -s $pid_file ]] || fail "the stubborn player started"
stubborn_pid=$(cat "$pid_file")
kill -0 "$stubborn_pid" 2>/dev/null && fail "the stubborn player survived the hard kill deadline"
pass "a player that ignores TERM is forcibly killed"

# Without a default sink there is nothing to play to, and login must not hang.
write_pw_play_stub
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
grep -q '^--kill-after=0.1s 0.5s wpctl ' "$timeout_log" ||
  fail "each sink probe has its own hard deadline" "$(cat "$timeout_log")"
pass "a session without an audio sink gives up quietly"
