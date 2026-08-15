#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command git
require_command pacman

TEST_HOME=$(mktemp -d)
SCRATCH=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$SCRATCH"' EXIT

# Restore ends by reapplying the current theme; shim omarchy-theme-set so
# the test never reaches into the live desktop.
mkdir -p "$SCRATCH/bin"
cat >"$SCRATCH/bin/omarchy-theme-set" <<EOF
#!/bin/bash
echo "\$@" >>"$SCRATCH/theme-set.log"
EOF
chmod +x "$SCRATCH/bin/omarchy-theme-set"

# The scripts commit; give them an identity without touching the real one.
printf '[user]\n\temail = test@omarchy\n\tname = omarchy-test\n' >"$SCRATCH/gitconfig"

run() {
  HOME="$TEST_HOME" PATH="$SCRATCH/bin:$PATH" GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig" GIT_CONFIG_SYSTEM=/dev/null "$@"
}

# --- seed a small fake system in an isolated HOME ---

mkdir -p "$TEST_HOME/.config/hypr" "$TEST_HOME/.config/alacritty" \
  "$TEST_HOME/.config/omarchy/themes" "$TEST_HOME/.local/share/applications" \
  "$TEST_HOME/.local/state/omarchy/current"

echo "monitor=eDP-1" >"$TEST_HOME/.config/hypr/hyprland.conf"
echo "junk" >"$TEST_HOME/.config/hypr/old.conf.bak.123"
echo "font = Test" >"$TEST_HOME/.config/alacritty/alacritty.toml"

cat >"$TEST_HOME/.local/share/applications/FakeApp.desktop" <<'EOF'
[Desktop Entry]
Exec=omarchy-launch-webapp "https://fake.example"
Icon=fakeapp
EOF

git init -q "$SCRATCH/theme-src"
echo "colors" >"$SCRATCH/theme-src/colors.toml"
git -C "$SCRATCH/theme-src" add -A
git -C "$SCRATCH/theme-src" -c user.email=t@t -c user.name=t commit -qm seed
git clone -q "$SCRATCH/theme-src" "$TEST_HOME/.config/omarchy/themes/fake-theme"
echo "fake-theme" >"$TEST_HOME/.local/state/omarchy/current/theme.name"

# An extras path that is itself a git clone: its files must be captured even
# though git would normally treat the copied directory as an embedded repo.
git clone -q "$SCRATCH/theme-src" "$TEST_HOME/.config/extratool"
echo "setting = 1" >"$TEST_HOME/.config/extratool/config.toml"

# --- first run seeds the repo ---

backup_dir="$TEST_HOME/omarchy-backup"

run "$ROOT/bin/omarchy-backup" >"$SCRATCH/backup0.log" 2>&1 ||
  fail "first backup initializes and runs cleanly" "$(cat "$SCRATCH/backup0.log")"
pass "first backup initializes and runs cleanly"

[[ -s $backup_dir/README.md && -s $backup_dir/backup.list ]] ||
  fail "first run seeds README.md and backup.list"
pass "first run seeds README.md and backup.list"

# --- second backup with a populated backup.list ---

echo ".config/extratool" >>"$backup_dir/backup.list"
run "$ROOT/bin/omarchy-backup" >"$SCRATCH/backup1.log" 2>&1 ||
  fail "backup runs cleanly" "$(cat "$SCRATCH/backup1.log")"
pass "backup runs cleanly"

[[ -f $backup_dir/config/hypr/hyprland.conf ]] || fail "backup mirrors hypr config"
pass "backup mirrors hypr config"

[[ ! -e $backup_dir/config/hypr/old.conf.bak.123 ]] || fail "backup excludes .bak noise"
pass "backup excludes .bak noise"

[[ -s $backup_dir/packages.txt ]] || fail "backup writes the package list"
pass "backup writes the package list"

grep -q "^fake-theme " "$backup_dir/themes.txt" || fail "backup records theme name and url"
pass "backup records theme name and url"

[[ -f $backup_dir/webapps/FakeApp.desktop ]] || fail "backup captures webapp launchers"
pass "backup captures webapp launchers"

[[ -f $backup_dir/extras/.config/extratool/config.toml ]] || fail "backup carries backup.list extras"
pass "backup carries backup.list extras"

[[ ! -e $backup_dir/extras/.config/extratool/.git ]] ||
  fail "backup strips nested .git so extras commit as files"
pass "backup strips nested .git so extras commit as files"

git -C "$backup_dir" ls-files --error-unmatch extras/.config/extratool/config.toml >/dev/null 2>&1 ||
  fail "extras from a cloned repo are tracked by the backup commit"
pass "extras from a cloned repo are tracked by the backup commit"

[[ -s $backup_dir/recovery/disk-map.txt && -s $backup_dir/recovery/cmdline.txt ]] ||
  fail "backup captures the recovery boot snapshot"
pass "backup captures the recovery boot snapshot"

git -C "$backup_dir" log -1 --format=%s | grep -q "^Backup from" || fail "backup commits its capture"
pass "backup commits its capture"

# --- damage the system, then restore ---

rm -rf "$TEST_HOME/.config/hypr" "$TEST_HOME/.config/extratool" \
  "$TEST_HOME/.config/omarchy/themes/fake-theme"
rm -f "$TEST_HOME/.local/share/applications/FakeApp.desktop"
echo "MODIFIED" >"$TEST_HOME/.config/alacritty/alacritty.toml"
recovery_before=$(cat "$backup_dir/recovery/disk-map.txt")

run "$ROOT/bin/omarchy-restore" configs themes webapps extras >"$SCRATCH/restore1.log" 2>&1 ||
  fail "restore runs cleanly" "$(cat "$SCRATCH/restore1.log")"
pass "restore runs cleanly"

[[ -f $TEST_HOME/.config/hypr/hyprland.conf ]] || fail "restore brings back deleted configs"
pass "restore brings back deleted configs"

[[ $(cat "$TEST_HOME/.config/alacritty/alacritty.toml") == "font = Test" ]] ||
  fail "restore replaces modified files"
pass "restore replaces modified files"

ls "$TEST_HOME/.config/alacritty/alacritty.toml.bak."* >/dev/null 2>&1 ||
  fail "restore keeps the modified version as a .bak aside"
pass "restore keeps the modified version as a .bak aside"

grep -q "1 files that differed" "$SCRATCH/restore1.log" ||
  fail "restore reports how many files it set aside"
pass "restore reports how many files it set aside"

[[ -d $TEST_HOME/.config/omarchy/themes/fake-theme/.git ]] || fail "restore reclones missing themes"
pass "restore reclones missing themes"

[[ -f $TEST_HOME/.local/share/applications/FakeApp.desktop ]] || fail "restore brings back webapps"
pass "restore brings back webapps"

[[ -f $TEST_HOME/.config/extratool/config.toml ]] || fail "restore brings back extras"
pass "restore brings back extras"

grep -q "fake-theme" "$SCRATCH/theme-set.log" || fail "restore reapplies the current theme"
pass "restore reapplies the current theme"

[[ $(cat "$backup_dir/recovery/disk-map.txt") == "$recovery_before" ]] ||
  fail "restore never touches the recovery snapshot"
pass "restore never touches the recovery snapshot"

# --- idempotence ---

baks_before=$(find "$TEST_HOME" -name "*.bak.*" | sort)
run "$ROOT/bin/omarchy-restore" configs themes webapps extras >"$SCRATCH/restore2.log" 2>&1 ||
  fail "a second restore exits cleanly" "$(cat "$SCRATCH/restore2.log")"
pass "a second restore exits cleanly"

baks_after=$(find "$TEST_HOME" -name "*.bak.*" | sort)
[[ $baks_before == "$baks_after" ]] || fail "a second restore changes nothing"
pass "a second restore changes nothing"

# Recovery output (mounts, EFI order) may legitimately shift between runs on a
# live machine, so only non-recovery paths must be unchanged after a restore.
run "$ROOT/bin/omarchy-backup" >"$SCRATCH/backup2.log" 2>&1
if ! grep -q "No changes since last backup" "$SCRATCH/backup2.log"; then
  git -C "$backup_dir" show --name-only --format= HEAD | grep -v "^recovery/" | grep -q . &&
    fail "a backup after a clean restore records no non-recovery changes" "$(cat "$SCRATCH/backup2.log")"
fi
pass "a backup after a clean restore records no non-recovery changes"
