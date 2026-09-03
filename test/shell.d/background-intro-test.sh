#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

intro_home="$test_tmp/home"
intro_runtime="$test_tmp/runtime"
intro_state="$intro_home/.local/state/omarchy/current"
theme_intro_dir="$intro_state/theme/intros"
user_intro_root="$intro_home/.config/omarchy/backgrounds/tokyo-night/intros"
background="$intro_state/theme/backgrounds/road.webp"
mkdir -p "$(dirname "$background")" "$theme_intro_dir" "$user_intro_root" "$intro_runtime"
printf 'matching still\n' >"$background"
printf 'theme video\n' >"$theme_intro_dir/road.mp4"
printf 'tokyo-night\n' >"$intro_state/theme.name"
ln -s "$background" "$intro_state/background"

background_hash=$(sha256sum "$background")
background_hash=${background_hash%% *}
user_intro_dir="$user_intro_root/$background_hash"
mkdir -p "$user_intro_dir"
printf '%s\n' "$background_hash" >"$theme_intro_dir/road.sha256"

resolved=$(HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" "$ROOT/bin/omarchy-theme-bg-boot-intro" --resolve-only)
[[ $resolved == "$theme_intro_dir/road.mp4" ]] || fail "the packaged intro matches the exact current still" "$resolved"

printf 'different still with the same name\n' >"$background"
resolved=$(HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" "$ROOT/bin/omarchy-theme-bg-boot-intro" --resolve-only)
[[ -z $resolved ]] || fail "a same-named replacement cannot inherit a mismatched packaged intro" "$resolved"

printf 'matching still\n' >"$background"
printf 'user video\n' >"$user_intro_dir/road.webm"
resolved=$(HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" "$ROOT/bin/omarchy-theme-bg-boot-intro" --resolve-only)
[[ $resolved == "$user_intro_dir/road.webm" ]] || fail "a matching user intro overrides the packaged intro" "$resolved"

printf '%s\n' "$background_hash" >"$user_intro_dir/road.disabled"
resolved=$(HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" "$ROOT/bin/omarchy-theme-bg-boot-intro" --resolve-only)
[[ -z $resolved ]] || fail "a matching per-background tombstone suppresses every intro" "$resolved"
rm "$user_intro_dir/road.disabled" "$user_intro_dir/road.webm"

toggle="$intro_home/.local/state/omarchy/toggles/background-intros-off"
marker="$intro_home/.local/state/omarchy/background-intro.boot-id"
mkdir -p "$(dirname "$toggle")"
touch "$toggle"
resolved=$(HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" OMARCHY_BOOT_ID=disabled-boot "$ROOT/bin/omarchy-theme-bg-boot-intro")
[[ -z $resolved && $(<"$marker") == "disabled-boot" ]] || fail "the global toggle consumes the current boot without playing"
rm "$toggle"
resolved=$(HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" OMARCHY_BOOT_ID=disabled-boot "$ROOT/bin/omarchy-theme-bg-boot-intro")
[[ -z $resolved ]] || fail "enabling midway through a boot does not start a delayed intro" "$resolved"

rm "$marker"
for index in {1..32}; do
  HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" OMARCHY_BOOT_ID=concurrent-boot "$ROOT/bin/omarchy-theme-bg-boot-intro" >"$test_tmp/output.$index" &
  intro_pids[$index]=$!
done
for intro_pid in "${intro_pids[@]}"; do
  wait "$intro_pid"
done
intro_count=$(awk 'NF { count += 1 } END { print count + 0 }' "$test_tmp"/output.*)
(( intro_count == 1 )) || fail "concurrent resolvers emit exactly one intro" "$intro_count"

pass "boot intros require an exact still and resolve once under concurrency"

command_bin="$test_tmp/bin"
command_log="$test_tmp/command-log"
mkdir -p "$command_bin"
ln -s "$ROOT/bin/omarchy-theme-bg-boot-intro" "$command_bin/omarchy-theme-bg-boot-intro"

cat >"$command_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf 'notification: %s\n' "$*" >>"$COMMAND_LOG"
SH
cat >"$command_bin/omarchy-shell" <<'SH'
#!/bin/bash
printf 'shell: %s\n' "$*" >>"$COMMAND_LOG"
SH
cat >"$command_bin/omarchy-theme-bg-current" <<'SH'
#!/bin/bash
printf 'Road\n'
SH
chmod +x "$command_bin"/omarchy-*

selected_video="$test_tmp/selected.mp4"
printf 'selected video\n' >"$selected_video"
mkdir "$test_tmp/not-a-video.mp4"
if PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" set "$test_tmp/not-a-video.mp4" >/dev/null 2>&1; then
  fail "setting an intro rejects a non-regular input"
fi
PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" set "$selected_video"
[[ -f $user_intro_dir/road.mp4 ]] || fail "setting an intro stores it under the current still hash"

resolved=$(PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" current)
[[ $resolved == "$user_intro_dir/road.mp4" ]] || fail "the public command reports the effective user intro" "$resolved"

same_stem_background="$intro_state/theme/backgrounds/road.png"
printf 'different same-stem background\n' >"$same_stem_background"
same_stem_hash=$(sha256sum "$same_stem_background")
same_stem_hash=${same_stem_hash%% *}
ln -nsf "$same_stem_background" "$intro_state/background"
PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" set "$selected_video"
[[ -f $user_intro_root/$same_stem_hash/road.mp4 && -f $user_intro_dir/road.mp4 ]] || fail "same-stem backgrounds keep independent intros"
PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" reset
[[ ! -e $user_intro_root/$same_stem_hash && -f $user_intro_dir/road.mp4 ]] || fail "resetting one same-stem background preserves the other intro"
ln -nsf "$background" "$intro_state/background"

PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" remove
[[ ! -e $user_intro_dir/road.mp4 && -f $user_intro_dir/road.disabled ]] || fail "removing an intro suppresses the packaged default for that exact still"
resolved=$(PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" current)
[[ $resolved == "None" ]] || fail "the public command reports a removed intro as none" "$resolved"

PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" reset
resolved=$(PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" current)
[[ $resolved == "$theme_intro_dir/road.mp4" ]] || fail "resetting an intro restores the matching packaged default" "$resolved"

PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" disable
resolved=$(PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" current)
[[ $resolved == "Disabled" ]] || fail "the current intro reports the global disabled state" "$resolved"
if PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" status; then
  fail "disabled boot intros report a disabled status"
fi
PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" enable
PATH="$command_bin:$PATH" HOME="$intro_home" XDG_RUNTIME_DIR="$intro_runtime" COMMAND_LOG="$command_log" "$ROOT/bin/omarchy-theme-bg-intro" status || fail "enabled boot intros report an enabled status"
grep -q '^shell: -q background cancelBootIntro$' "$command_log" || fail "removing or disabling an intro stops active playback"

pass "users can set, remove, restore, enable, and disable boot intros"

migration_home="$test_tmp/migration-home"
migration_bin="$test_tmp/migration-bin"
migration_calls="$test_tmp/migration-calls"
mkdir -p "$migration_home/.local/state/omarchy/current" "$migration_bin"
printf 'tokyo-night\n' >"$migration_home/.local/state/omarchy/current/theme.name"
cat >"$migration_bin/omarchy-theme-refresh" <<'SH'
#!/bin/bash
printf 'refresh\n' >>"$MIGRATION_CALLS"
SH
chmod +x "$migration_bin/omarchy-theme-refresh"

HOME="$migration_home" PATH="$migration_bin:$PATH" MIGRATION_CALLS="$migration_calls" OMARCHY_BOOT_ID=migration-boot bash -euo pipefail "$ROOT/migrations/1788281348.sh" >/dev/null
[[ $(<"$migration_calls") == "refresh" ]] || fail "the migration refreshes an active Tokyo Night theme"
[[ $(<"$migration_home/.local/state/omarchy/background-intro.boot-id") == "migration-boot" ]] || fail "the migration defers a newly installed intro until the next boot"

pass "the migration does not start a boot intro during an update"

run_node_test <<'JS'
const fs = require('fs')
const backgroundQml = fs.readFileSync(path.join(root, 'shell/plugins/background/Background.qml'), 'utf8')

assert(
  backgroundQml.includes('bootIntroRequestVersion !== root.backgroundVersion')
    && backgroundQml.includes('if (sessionObscured) cancelBootIntro()')
    && backgroundQml.includes('if (fullscreenActive) cancelBootIntro()'),
  'a stale or obscured boot intro cannot appear later in the session'
)
assert(
  backgroundQml.includes('function cancelBootIntro(): void')
    && backgroundQml.includes('bootIntroFinishedScreens >= Quickshell.screens.length')
    && backgroundQml.includes('root.bootIntroFinishedScreens = Math.max(0, root.bootIntroFinishedScreens - 1)')
    && backgroundQml.includes('onFinished: panel.handleBootIntroFinished()'),
  'the shell exposes cancellation and waits for every monitor to finish'
)
JS

for pairing in 0-winding-road 3-sunset-lake; do
  expected_hash=$(<"$ROOT/themes/tokyo-night/intros/$pairing.sha256")
  actual_hash=$(sha256sum "$ROOT/themes/tokyo-night/backgrounds/$pairing.webp")
  actual_hash=${actual_hash%% *}
  [[ $actual_hash == "$expected_hash" ]] || fail "Tokyo Night $pairing intro is bound to its exact still"
done

pass "packaged Tokyo Night intros match their still backgrounds"
