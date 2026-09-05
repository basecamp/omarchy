#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

backup="$ROOT/bin/omarchy-backup"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
fake_bin="$test_tmp/bin"
home="$test_tmp/home"
mkdir -p "$fake_bin" "$home/.config/hypr" "$home/.config/omarchy"
printf 'monitor=DP-1\n' >"$home/.config/hypr/monitors.lua"
printf 'bind = SUPER, Return, exec, foot\n' >"$home/.config/hypr/bindings.lua"
printf '{"bar":{}}\n' >"$home/.config/omarchy/shell.json"

cat >"$fake_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
exit 1
STUB
cat >"$fake_bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$fake_bin/omarchy-version" <<'STUB'
#!/bin/bash
echo test-version
STUB
cat >"$fake_bin/rclone" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG"
case "$1" in
listremotes) echo 'cloud:' ;;
copyto)
  source=$2
  destination=$3
  [[ $source == cloud:* ]] && source="$TEST_CLOUD/${source#cloud:}"
  [[ $destination == cloud:* ]] && destination="$TEST_CLOUD/${destination#cloud:}"
  mkdir -p "$(dirname "$destination")"
  cp "$source" "$destination"
  ;;
esac
STUB
chmod +x "$fake_bin"/*

config="$home/.config/omarchy/backup/settings.conf"
mkdir -p "${config%/*}"
printf 'remote=cloud\npath=settings\ndevice=laptop\n' >"$config"
mkdir -p "$test_tmp/cloud/settings/laptop"

TEST_LOG="$test_tmp/calls" TEST_CLOUD="$test_tmp/cloud" HOME="$home" XDG_CONFIG_HOME="$home/.config" PATH="$fake_bin:$PATH" \
  bash "$backup" create >/dev/null
[[ -f "$test_tmp/cloud/settings/laptop/latest-personal-home.tar.gz" ]] || fail "backup creates a latest cloud archive"
tar -tzf "$test_tmp/cloud/settings/laptop/latest-personal-home.tar.gz" | grep -qx './.config/hypr/monitors.lua' ||
  fail "backup includes Hyprland settings"
tar -tzf "$test_tmp/cloud/settings/laptop/latest-personal-home.tar.gz" | grep -q 'omarchy/backup' &&
  fail "backup excludes its destination configuration"
printf 'important project\n' >"$home/project.txt"
TEST_LOG="$test_tmp/calls" TEST_CLOUD="$test_tmp/cloud" HOME="$home" XDG_CONFIG_HOME="$home/.config" PATH="$fake_bin:$PATH" \
  bash "$backup" create >/dev/null
tar -tzf "$test_tmp/cloud/settings/laptop/latest-personal-home.tar.gz" | grep -qx './project.txt' ||
  fail "backup includes work stored in home"
pass "backup archives the home directory without cloud credentials or destination state"

rm -rf "$home/.config/hypr" "$home/project.txt"
TEST_LOG="$test_tmp/calls" TEST_CLOUD="$test_tmp/cloud" HOME="$home" XDG_CONFIG_HOME="$home/.config" PATH="$fake_bin:$PATH" \
  bash "$backup" restore --yes >/dev/null
[[ $(cat "$home/.config/hypr/monitors.lua") == 'monitor=DP-1' ]] || fail "restore returns desktop settings"
[[ $(cat "$home/project.txt") == 'important project' ]] || fail "restore returns work stored in home"
pass "restore returns the latest archive after explicit confirmation bypass"

TEST_LOG="$test_tmp/calls" TEST_CLOUD="$test_tmp/cloud" HOME="$home" XDG_CONFIG_HOME="$home/.config" PATH="$fake_bin:$PATH" \
  bash "$backup" restore --dry-run >/dev/null
! grep -q 'restore' "$test_tmp/calls" || true
pass "restore dry-run previews without changing home-directory files"

profile_remote="$test_tmp/profile.git"
profile_seed="$test_tmp/profile-seed"
git init --bare --quiet "$profile_remote"
git init --quiet "$profile_seed"
git -C "$profile_seed" -c user.name=test -c user.email=test@example.invalid commit --quiet --allow-empty -m 'Initialize shared profile'
git -C "$profile_seed" branch -M main
git -C "$profile_seed" remote add origin "$profile_remote"
git -C "$profile_seed" push --quiet origin main
git --git-dir="$profile_remote" symbolic-ref HEAD refs/heads/main
printf 'remote=cloud\npath=settings\ndevice=laptop\nprofile_repo=%s\n' "$profile_remote" >"$config"

TEST_LOG="$test_tmp/calls" TEST_CLOUD="$test_tmp/cloud" HOME="$home" XDG_CONFIG_HOME="$home/.config" PATH="$fake_bin:$PATH" \
  bash "$backup" sync push >/dev/null
git --git-dir="$profile_remote" show-ref --verify --quiet refs/heads/profiles/laptop ||
  fail "sync push publishes a versioned device profile"
printf 'add_newline = false\n' >"$home/.config/starship.toml"
sed -i 's/device=laptop/device=desktop/' "$config"
TEST_LOG="$test_tmp/calls" TEST_CLOUD="$test_tmp/cloud" HOME="$home" XDG_CONFIG_HOME="$home/.config" PATH="$fake_bin:$PATH" \
  bash "$backup" sync push >/dev/null
sed -i 's/device=desktop/device=laptop/' "$config"
TEST_LOG="$test_tmp/calls" TEST_CLOUD="$test_tmp/cloud" HOME="$home" XDG_CONFIG_HOME="$home/.config" PATH="$fake_bin:$PATH" \
  bash "$backup" sync merge >/dev/null
git --git-dir="$profile_remote" show main:.config/starship.toml | grep -qx 'add_newline = false' ||
  fail "sync merge combines versioned device profiles into shared latest"
(( $(git --git-dir="$profile_remote" rev-list --parents -n 1 main | wc -w) > 2 )) ||
  fail "sync merge records shared latest as a merge commit"
pass "sync versions device profiles and merges them into shared latest"
