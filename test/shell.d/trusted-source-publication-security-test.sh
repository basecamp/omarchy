#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command unshare
require_command chroot
require_command setpriv
require_command cc

test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT
rootfs=$test_tmp/root
fixture=$test_tmp/fixture
mkdir -p "$rootfs" "$fixture"

cat >"$fixture/sudo.c" <<'C'
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

static const char *live = "/run/sudo-live";

int main(int argc, char **argv) {
  int noninteractive = 0;
  int index = 1;

  if (setgid(0) != 0 || setuid(0) != 0) return 120;
  if (argc == 2 && strcmp(argv[1], "-k") == 0) {
    unlink(live);
    return 0;
  }
  if (index < argc && strcmp(argv[index], "-n") == 0) {
    noninteractive = 1;
    index++;
  }
  if (index < argc && strcmp(argv[index], "--") == 0) index++;
  if (noninteractive && access(live, F_OK) != 0) return 1;

  int fd = open(live, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  if (fd < 0) return 121;
  close(fd);
  if (index >= argc) return 2;
  execv(argv[index], &argv[index]);
  return errno == ENOENT ? 127 : 126;
}
C
cc -O2 -Wall -Wextra -o "$fixture/sudo" "$fixture/sudo.c"
chmod 4755 "$fixture/sudo"

cat >"$fixture/namespace-test.sh" <<'TEST'
#!/bin/bash
set -euo pipefail
[[ ${OMARCHY_TEST_DEBUG:-false} != true ]] || set -x

rootfs=$1
repo=$2
fixture=$3

mount --make-rprivate /
mkdir -p \
  "$rootfs"/{boot,dev,etc,home,host-bin,host-lib,opt,proc,run,sys/power,tmp,usr/bin,usr/lib,usr/share,var} \
  "$rootfs/usr/lib/systemd" "$rootfs/usr/lib/firefox"
# The production scripts use Bash process substitution, which is opened via
# /dev/fd after dropping to the modeled desktop uid. Normalize these traversal
# boundaries independently of the caller's umask.
chmod 0755 "$rootfs" "$rootfs"/{boot,dev,etc,home,opt,proc,run,sys,usr,var} "$rootfs/usr"/{bin,lib,share}
chmod 1777 "$rootfs/tmp"
touch "$rootfs/dev/null"
ln -s /proc/self/fd "$rootfs/dev/fd"
ln -s /proc/self/fd/0 "$rootfs/dev/stdin"

mount --bind /usr/bin "$rootfs/host-bin"
mount --bind /usr/lib "$rootfs/host-lib"
mount --bind /dev/null "$rootfs/dev/null"
mount -t proc proc "$rootfs/proc"
mount -t tmpfs -o mode=0755,suid tmpfs "$rootfs/usr/bin"
cleanup_namespace() {
  umount "$rootfs/dev/null" "$rootfs/proc" "$rootfs/usr/bin" "$rootfs/host-bin" "$rootfs/host-lib" 2>/dev/null || true
  chown -R 0:0 "$rootfs" 2>/dev/null || true
}
trap cleanup_namespace EXIT
ln -s usr/bin "$rootfs/bin"
ln -s usr/lib "$rootfs/lib"
ln -s usr/lib "$rootfs/lib64"
ln -s bin "$rootfs/usr/sbin"

for entry in /usr/lib/*; do
  name=${entry##*/}
  [[ $name == systemd || $name == firefox ]] && continue
  ln -s "/host-lib/$name" "$rootfs/usr/lib/$name"
done

host_commands=(
  awk bash cat chmod cp date dirname env find free grep id install ln mkdir mktemp mv
  readlink realpath rm sed setpriv sleep stat test tee timeout touch true
)
for command in "${host_commands[@]}"; do
  ln -s "/host-bin/$command" "$rootfs/usr/bin/$command"
done

install -m 4755 "$fixture/sudo" "$rootfs/usr/bin/sudo"

make_stub() {
  local name=$1
  shift
  rm -f "$rootfs/usr/bin/$name"
  {
    echo '#!/bin/bash'
    printf '%s\n' "$@"
  } >"$rootfs/usr/bin/$name"
  chmod 0755 "$rootfs/usr/bin/$name"
}

make_stub gum 'exit 0'
make_stub supergfxctl 'printf "Hybrid\n"'
make_stub systemctl 'exit 0'
make_stub limine-update 'exit 0'
make_stub limine-snapper-sync 'exit 0'
make_stub limine-mkinitcpio 'exit 0'
make_stub btrfs \
  'if [[ $* == *"map-swapfile"* ]]; then printf "123\n"; fi' \
  'exit 0'
make_stub swaplabel 'exit 0'
make_stub swapon \
  'if [[ ${1:-} == --show ]]; then printf "/swap/swapfile\n"; fi' \
  'exit 0'
make_stub findmnt 'printf "/dev/mapper/root[/root]\n"'
make_stub pacman \
  'printf "TX" >>/run/pacman-args' \
  'printf " <%s>" "$@" >>/run/pacman-args' \
  'printf "\n" >>/run/pacman-args'
make_stub install \
  '[[ ! -e /run/fail-install ]] || exit 77' \
  'args=()' \
  'while (( $# )); do' \
  '  case $1 in -o|-g) shift 2 ;; *) args+=("$1"); shift ;; esac' \
  'done' \
  'exec /host-bin/install "${args[@]}"'

mkdir -p "$rootfs/usr/share/omarchy"/{bin,config,default/firefox,default/limine,default/pacman,default/systemd/system-sleep,default/systemd/system/supergfxd.service.d,install/helpers}
cp "$repo/install/helpers/browser-policy.sh" "$rootfs/usr/share/omarchy/install/helpers/browser-policy.sh"
cp "$repo/install/helpers/as-root.sh" "$rootfs/usr/share/omarchy/install/helpers/as-root.sh"
printf 'GOOD FORCE IGPU\n' >"$rootfs/usr/share/omarchy/default/systemd/system-sleep/force-igpu"
printf 'GOOD KEYBOARD\n' >"$rootfs/usr/share/omarchy/default/systemd/system-sleep/keyboard-backlight"
printf 'GOOD DELAY\n' >"$rootfs/usr/share/omarchy/default/systemd/system/supergfxd.service.d/delay-start.conf"
install -Dm755 "$rootfs/usr/share/omarchy/default/systemd/system-sleep/force-igpu" \
  "$rootfs/usr/lib/systemd/system-sleep/omarchy-force-igpu"
install -Dm755 "$rootfs/usr/share/omarchy/default/systemd/system-sleep/keyboard-backlight" \
  "$rootfs/usr/lib/systemd/system-sleep/omarchy-keyboard-backlight"
printf 'GOOD LIMINE\n' >"$rootfs/usr/share/omarchy/default/limine/limine.conf"
printf '{"policies":{"GOOD":true}}\n' >"$rootfs/usr/share/omarchy/default/firefox/policies.json"
printf 'GOOD FLAGS\n' >"$rootfs/usr/share/omarchy/config/chromium-flags.conf"
printf 'GOOD PACMAN\n' >"$rootfs/usr/share/omarchy/default/pacman/pacman-stable.conf"
printf 'GOOD MIRROR\n' >"$rootfs/usr/share/omarchy/default/pacman/mirrorlist-stable"
printf 'good-package\n' >"$rootfs/usr/share/omarchy/install/omarchy-base.packages"

make_source_stub() {
  local name=$1
  shift
  {
    echo '#!/bin/bash'
    printf '%s\n' "$@"
  } >"$rootfs/usr/share/omarchy/bin/$name"
  chmod 0755 "$rootfs/usr/share/omarchy/bin/$name"
}
make_source_stub omarchy-cmd-missing 'exit 1'
make_source_stub omarchy-pkg-add \
  '/usr/bin/sudo /usr/bin/true' \
  'printf "PKG %s\n" "$*" >>/run/browser-trace'
make_source_stub omarchy-pkg-aur-add \
  '/usr/bin/sudo /usr/bin/true' \
  'printf "AUR %s\n" "$*" >>/run/browser-trace'
make_source_stub omarchy-system-reboot 'printf "REBOOT\n" >>/run/reboot-trace'
make_source_stub omarchy-install-chromium-copy-url 'printf "COPY URL\n" >>/run/browser-trace'
make_source_stub omarchy-install-chromium-ytdlp 'printf "YTDLP\n" >>/run/browser-trace'
make_source_stub omarchy-theme-set-browser \
  'if /usr/bin/sudo -n /usr/bin/touch /browser-reused; then exit 91; fi' \
  'printf "THEME COLD\n" >>/run/browser-trace'
make_source_stub omarchy-hook \
  'if /usr/bin/sudo -n /usr/bin/touch /hook-reused; then printf "HOOK REUSED\n" >>/run/hook-trace; exit 92; fi' \
  'printf "HOOK BLOCKED %s\n" "$*" >>/run/hook-trace'

# The fixture represents a packaged, root-owned source tree. Normalize it
# independently of the shell that launched this test so permissive and
# restrictive caller umasks cannot create either writable or unreadable
# package fixtures.
find "$rootfs/usr/share/omarchy" -type d -exec chmod 0755 {} +
find "$rootfs/usr/share/omarchy" -type f -exec chmod 0644 {} +
find "$rootfs/usr/share/omarchy/bin" -type f -exec chmod 0755 {} +

mkdir -p "$rootfs/malicious/bin" "$rootfs/malicious/default/systemd/system-sleep" "$rootfs/malicious/default/limine" "$rootfs/malicious/install/helpers"
printf 'PWNED\n' >"$rootfs/malicious/default/systemd/system-sleep/force-igpu"
printf 'PWNED\n' >"$rootfs/malicious/default/systemd/system-sleep/keyboard-backlight"
printf 'PWNED\n' >"$rootfs/malicious/default/limine/limine.conf"
cat >"$rootfs/malicious/bin/sudo" <<'STUB'
#!/bin/bash
touch /malicious-path-ran
exit 93
STUB
chmod 0755 "$rootfs/malicious/bin/sudo"
cat >"$rootfs/malicious/install/helpers/browser-policy.sh" <<'STUB'
touch /malicious-helper-ran
STUB

cp "$repo/bin/omarchy-toggle-hybrid-gpu" "$rootfs/run/toggle"
cp "$repo/bin/omarchy-refresh-limine" "$rootfs/run/limine"
cp "$repo/bin/omarchy-hibernation-setup" "$rootfs/run/hibernate"
cp "$repo/bin/omarchy-install-browser" "$rootfs/run/browser"
cp "$repo/bin/omarchy-reinstall-pkgs" "$rootfs/run/reinstall"
chmod 0755 "$rootfs/run"/{toggle,limine,hibernate,browser,reinstall}

printf '0123456789abcdef0123456789abcdef\n' >"$rootfs/etc/machine-id"
printf 'root:x:0:0:root:/root:/bin/bash\ntest:x:1000:1000:test:/home/test:/bin/bash\n' >"$rootfs/etc/passwd"
printf 'root:x:0:\ntest:x:1000:\n' >"$rootfs/etc/group"
cat >"$rootfs/etc/supergfxd.conf" <<'CONF'
{"mode": "Hybrid", "vfio_enable": false}
CONF
printf '/swap/swapfile none swap defaults 0 0\n' >"$rootfs/etc/fstab"
printf '1\n' >"$rootfs/sys/power/image_size"
printf 'deep\n' >"$rootfs/sys/power/mem_sleep"
mkdir -p "$rootfs/home/test"
chown 1000:1000 "$rootfs/home/test"
chmod 0700 "$rootfs/home/test"
mkdir -p "$rootfs/etc/pacman.d" "$rootfs/etc/systemd/system" "$rootfs/usr/lib/systemd/system-sleep"
printf 'OLD PACMAN\n' >"$rootfs/etc/pacman.conf"
printf 'OLD MIRROR\n' >"$rootfs/etc/pacman.d/mirrorlist"

# These model ordinary root-owned system and attacker-controlled fixtures that
# the desktop user must be able to traverse or read. Keep their modes realistic
# regardless of the umask inherited by the namespace helper.
chmod 0755 \
  "$rootfs/etc/pacman.d" "$rootfs/etc/systemd" "$rootfs/etc/systemd/system" \
  "$rootfs/sys/power" "$rootfs/usr/lib/firefox" "$rootfs/usr/lib/systemd" \
  "$rootfs/usr/lib/systemd/system-sleep"
chmod 0644 \
  "$rootfs/etc/machine-id" "$rootfs/etc/passwd" "$rootfs/etc/group" \
  "$rootfs/etc/supergfxd.conf" "$rootfs/etc/fstab" "$rootfs/etc/pacman.conf" \
  "$rootfs/etc/pacman.d/mirrorlist" "$rootfs/sys/power/image_size" \
  "$rootfs/sys/power/mem_sleep"
find "$rootfs/malicious" -type d -exec chmod 0755 {} +
find "$rootfs/malicious" -type f -exec chmod 0644 {} +
chmod 0755 "$rootfs/malicious/bin/sudo"
chmod 1777 "$rootfs/run"

run_user() {
  local bash_args=()
  [[ ${OMARCHY_TEST_DEBUG:-false} != true ]] || bash_args=(-x)
  chroot "$rootfs" /usr/bin/setpriv --reuid=1000 --regid=1000 --clear-groups \
    /usr/bin/env -i HOME=/home/test USER=test LOGNAME=test \
    OMARCHY_PATH=/malicious PATH=/malicious/bin:/usr/bin \
    /usr/bin/bash "${bash_args[@]}" "$@"
}

rm -f "$rootfs/etc/omarchy.conf" "$rootfs/run/sudo-live"
umask 000
run_user /run/toggle
grep -Fxq 'GOOD FORCE IGPU' "$rootfs/usr/lib/systemd/system-sleep/omarchy-force-igpu"
[[ -f $rootfs/etc/omarchy/force-igpu && ! -L $rootfs/etc/omarchy/force-igpu ]]
[[ $(stat -c %a "$rootfs/etc/omarchy/force-igpu") == 644 ]]
[[ $(stat -c %u:%g "$rootfs/etc/omarchy/force-igpu") == 0:0 ]]
delay_link="$rootfs/etc/systemd/system/supergfxd.service.d/10-omarchy-delay-start.conf"
[[ -L $delay_link ]]
[[ $(readlink "$delay_link") == /usr/share/omarchy/default/systemd/system/supergfxd.service.d/delay-start.conf ]]
[[ ! -e $rootfs/usr/lib/systemd/system-sleep/force-igpu ]]
[[ ! -e $rootfs/etc/systemd/system/supergfxd.service.d/delay-start.conf ]]
[[ ! -e $rootfs/malicious-path-ran ]]
echo 'PASS toggle'

printf 'OLD LIMINE\n' >"$rootfs/boot/limine.conf"
run_user /run/limine
grep -Fxq 'GOOD LIMINE' "$rootfs/boot/limine.conf"
grep -Fxq 'OLD LIMINE' "$rootfs/boot/limine.conf.bak"
[[ $(stat -c %a "$rootfs/boot/limine.conf") == 644 ]]
[[ $(stat -c %u:%g "$rootfs/boot/limine.conf") == 0:0 ]]
echo 'PASS limine'

printf 'STILL BOOTABLE\n' >"$rootfs/boot/limine.conf"
touch "$rootfs/run/fail-install"
if run_user /run/limine >"$rootfs/run/limine-fail.out" 2>&1; then exit 31; fi
rm -f "$rootfs/run/fail-install"
grep -Fxq 'STILL BOOTABLE' "$rootfs/boot/limine.conf"
echo 'PASS limine-failure'

run_user /run/hibernate --force --no-rebuild
grep -Fxq 'GOOD KEYBOARD' "$rootfs/usr/lib/systemd/system-sleep/omarchy-keyboard-backlight"
[[ $(stat -c %a "$rootfs/usr/lib/systemd/system-sleep/omarchy-keyboard-backlight") == 755 ]]
[[ $(stat -c %u:%g "$rootfs/usr/lib/systemd/system-sleep/omarchy-keyboard-backlight") == 0:0 ]]
[[ ! -e $rootfs/usr/lib/systemd/system-sleep/keyboard-backlight ]]
echo 'PASS hibernate'

run_user /run/browser firefox
grep -Fxq 'PKG firefox' "$rootfs/run/browser-trace"
grep -q '"GOOD":true' "$rootfs/usr/lib/firefox/distribution/policies.json"
[[ $(stat -c %u:%g "$rootfs/usr/lib/firefox/distribution/policies.json") == 0:0 ]]
[[ ! -e $rootfs/malicious-helper-ran && ! -e $rootfs/browser-reused ]]
[[ ! -e $rootfs/run/sudo-live ]]
echo 'PASS browser'

rm -f "$rootfs/run/pacman-args" "$rootfs/run/hook-trace" "$rootfs/run/sudo-live"
run_user /run/reinstall
grep -Fxq 'HOOK BLOCKED pre-refresh-pacman' "$rootfs/run/hook-trace"
[[ ! -e $rootfs/hook-reused && ! -e $rootfs/run/sudo-live ]]
[[ $(grep -c '^TX' "$rootfs/run/pacman-args") == 3 ]]
grep -Fq '<--needed> <--> <good-package>' "$rootfs/run/pacman-args"
echo 'PASS reinstall'

printf '%s\n' '--config' >"$rootfs/usr/share/omarchy/install/omarchy-base.packages"
rm -f "$rootfs/run/pacman-args"
if run_user /run/reinstall >"$rootfs/run/reinstall-invalid.out" 2>&1; then exit 32; fi
[[ ! -e $rootfs/run/pacman-args ]]
echo 'PASS package-injection'
printf 'good-package\n' >"$rootfs/usr/share/omarchy/install/omarchy-base.packages"

mv "$rootfs/usr/share/omarchy/default/limine/limine.conf" "$rootfs/usr/share/omarchy/default/limine/limine.conf.real"
ln -s /malicious/default/limine/limine.conf "$rootfs/usr/share/omarchy/default/limine/limine.conf"
printf 'SOURCE LINK UNCHANGED\n' >"$rootfs/boot/limine.conf"
if run_user /run/limine >"$rootfs/run/source-symlink.out" 2>&1; then exit 36; fi
grep -Fxq 'SOURCE LINK UNCHANGED' "$rootfs/boot/limine.conf"
rm "$rootfs/usr/share/omarchy/default/limine/limine.conf"
mv "$rootfs/usr/share/omarchy/default/limine/limine.conf.real" "$rootfs/usr/share/omarchy/default/limine/limine.conf"
echo 'PASS source-symlink'

dev='/home/test/Dév $pace "quote" `tick` \\slash'
mkdir -p "$rootfs$dev/default/limine"
printf 'DEV LIMINE\n' >"$rootfs$dev/default/limine/limine.conf"
chown -R 1000:1000 "$rootfs$dev"
chmod -R go-w "$rootfs$dev"
quoted=$dev
quoted=${quoted//\\/\\\\}; quoted=${quoted//\"/\\\"}
quoted=${quoted//\$/\\\$}; quoted=${quoted//\`/\\\`}
printf 'export OMARCHY_PATH="%s"\n' "$quoted" >"$rootfs/etc/omarchy.conf"
chmod 0644 "$rootfs/etc/omarchy.conf"
printf 'PRE DEV\n' >"$rootfs/boot/limine.conf"
run_user /run/limine
grep -Fxq 'DEV LIMINE' "$rootfs/boot/limine.conf"
echo 'PASS dev-link'

printf 'export OMARCHY_PATH="/malicious"\n' >"$rootfs/etc/omarchy-target"
ln -sf omarchy-target "$rootfs/etc/omarchy.conf"
printf 'UNCHANGED\n' >"$rootfs/boot/limine.conf"
if run_user /run/limine >"$rootfs/run/config-symlink.out" 2>&1; then exit 33; fi
grep -Fxq 'UNCHANGED' "$rootfs/boot/limine.conf"
echo 'PASS config-symlink'

rm -f "$rootfs/etc/omarchy.conf"
printf 'export OMARCHY_PATH="/malicious"\n' >"$rootfs/etc/omarchy.conf"
chmod 0666 "$rootfs/etc/omarchy.conf"
if run_user /run/limine >"$rootfs/run/config-mode.out" 2>&1; then exit 34; fi
grep -Fxq 'UNCHANGED' "$rootfs/boot/limine.conf"
echo 'PASS config-mode'

chmod 0644 "$rootfs/etc/omarchy.conf"
printf 'export OMARCHY_PATH=/malicious\n' >"$rootfs/etc/omarchy.conf"
if run_user /run/limine >"$rootfs/run/config-grammar.out" 2>&1; then exit 35; fi
grep -Fxq 'UNCHANGED' "$rootfs/boot/limine.conf"
echo 'PASS config-grammar'
TEST
chmod 0755 "$fixture/namespace-test.sh"

output=$(unshare --user --map-auto --map-root-user --mount --pid --fork --kill-child \
  "$fixture/namespace-test.sh" "$rootfs" "$ROOT" "$fixture" 2>&1) ||
  fail "trusted-source publication namespace regression completes" "$output"

expected=(
  'PASS toggle'
  'PASS limine'
  'PASS limine-failure'
  'PASS hibernate'
  'PASS browser'
  'PASS reinstall'
  'PASS package-injection'
  'PASS source-symlink'
  'PASS dev-link'
  'PASS config-symlink'
  'PASS config-mode'
  'PASS config-grammar'
)
for marker in "${expected[@]}"; do
  grep -Fxq "$marker" <<<"$output" || fail "focused namespace case completed: $marker" "$output"
done

pass "inherited source and PATH cannot publish privileged boot, browser, or package content"
pass "sleep-hook executable code remains package-owned while runtime state stays minimal"
pass "root-authorized default and escaped dev-link sources remain supported"
pass "unsafe config boundaries and package option injection fail before privileged transactions"
pass "reinstall invalidates sudo before its final user hook"

for command in \
  bin/omarchy-toggle-hybrid-gpu \
  bin/omarchy-refresh-limine \
  bin/omarchy-hibernation-setup \
  bin/omarchy-install-browser \
  bin/omarchy-reinstall-pkgs; do
  [[ $(stat -c %a "$ROOT/$command") == 755 ]] || fail "$command remains executable"
done
pass "all hardened user-facing commands retain mode 0755"
