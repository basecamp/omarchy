#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 --staging <package-root> <runtime-version>" >&2
  exit 64
}

fail() {
  echo "secure plugin package verification failed: $1" >&2
  exit 1
}

needed_libraries() {
  readelf -d "$1" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p'
}

verify_elf() {
  local elf=$1 kind=$2 allowed=$3 required=$4 identity resolution needed runpath

  identity=$(file -b "$elf")
  if [[ $kind == "pie" ]]; then
    [[ $identity == *"ELF 64-bit LSB pie executable, x86-64"* ]] || fail "$(basename "$elf") is not an x86-64 PIE executable"
  else
    [[ $identity == *"ELF 64-bit LSB shared object, x86-64"* ]] || fail "$(basename "$elf") is not an x86-64 shared object"
  fi

  readelf -W -l "$elf" | grep -Eq 'GNU_STACK.*RW[[:space:]]' || fail "$(basename "$elf") has no non-executable GNU stack declaration"
  readelf -W -l "$elf" | grep -q 'GNU_RELRO' || fail "$(basename "$elf") has no GNU RELRO segment"
  if readelf -d "$elf" | grep -q '(RPATH)'; then
    fail "$(basename "$elf") contains an RPATH"
  fi
  runpath=$(readelf -d "$elf" | sed -n 's/.*(RUNPATH).*\[\([^]]*\)\].*/\1/p')
  [[ -z $runpath || $runpath == '$ORIGIN:$ORIGIN/../lib' ]] || fail "$(basename "$elf") contains an unsafe RUNPATH"

  while IFS= read -r needed; do
    [[ $needed =~ $allowed ]] || fail "$(basename "$elf") has unexpected DT_NEEDED $needed"
  done < <(needed_libraries "$elf")
  needed_libraries "$elf" | grep -Fx "$required" >/dev/null || fail "$(basename "$elf") omits required DT_NEEDED $required"

  if ! resolution=$(ldd -r "$elf" 2>&1); then
    fail "$(basename "$elf") dependency resolution failed"
  fi
  if grep -Eq 'not found|undefined symbol' <<<"$resolution"; then
    fail "$(basename "$elf") has an unresolved runtime dependency"
  fi
}

if (( $# != 3 )) || [[ $1 != "--staging" ]]; then
  usage
fi

staging=$2
version=$3
[[ -d $staging ]] || fail "staging root is absent"
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "runtime version is not numeric semver"

root=$staging/usr/lib/omarchy/plugin-security/$version
manifest=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/package-manifest-v1.txt
[[ -d $root && ! -L $root ]] || fail "versioned runtime root is absent or linked"

actual=$(cd "$root" && find . -type f -printf '%m %P\n' | LC_ALL=C sort)
expected=$(LC_ALL=C sort "$manifest")
[[ $actual == "$expected" ]] || fail "installed file manifest differs from package-manifest-v1.txt"

while read -r mode relative; do
  path=$root/$relative
  [[ -f $path && ! -L $path ]] || fail "manifest member is absent or linked: $relative"
  [[ $(stat -c '%a' "$path") == "$mode" ]] || fail "manifest member has wrong mode: $relative"
  if (( (8#$mode & 8#6022) != 0 )); then
    fail "manifest member has unsafe permissions: $relative"
  fi
done < "$manifest"

while IFS= read -r directory; do
  [[ ! -L $directory ]] || fail "runtime directory is linked: $directory"
  [[ $(stat -c '%a' "$directory") == "755" ]] || fail "runtime directory mode is not 755: $directory"
done < <(find "$root" -type d -print)

version_roots=$(find "$staging/usr/lib/omarchy/plugin-security" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort)
[[ $version_roots == "$version" ]] || fail "staging package contains another runtime version"

for forbidden in usr/bin usr/lib/systemd usr/share/omarchy shell config default migrations; do
  [[ ! -e $staging/$forbidden ]] || fail "package writes outside its owned versioned root: $forbidden"
done

worker=$root/bin/omarchy-plugin-qml-worker
bridge=$root/qml/Omarchy/PluginHost/libomarchy-plugin-host-bridge.so
runtime_dependencies=$root/metadata/runtime-dependencies-v1.txt

if ! qt6_base_package=$(/usr/bin/pacman -Q -- qt6-base 2>/dev/null); then
  fail "installed qt6-base package cannot be queried"
fi
expected_dependencies=$(cat <<EOF
bubblewrap
glibc
libgcc
libglvnd
libseccomp
libstdc++
libxkbcommon
${qt6_base_package/ /=}
qt6-declarative
quickshell
systemd-libs
EOF
)
[[ $(<"$runtime_dependencies") == $expected_dependencies ]] ||
  fail "runtime dependency contract differs from the required Arch package set or qt6-base build"

set +e
"$worker" >/dev/null 2>&1
worker_status=$?
set -e
(( worker_status == 78 )) || fail "private worker does not reject direct execution"
readelf -Ws "$worker" | grep -F '@Qt_6_PRIVATE_API' >/dev/null ||
  fail "omarchy-plugin-qml-worker omits expected Qt private ABI imports"

qt_allowed='^(libQt6(Quick|OpenGL|Gui|Qml|Network|Core)\.so\.6|lib(GLX|OpenGL)\.so\.0|libseccomp\.so\.2|libxkbcommon\.so\.0|libstdc\+\+\.so\.6|libm\.so\.6|libgcc_s\.so\.1|libc\.so\.6)$'
bridge_allowed='^(libQt6(Quick|OpenGL|Gui|Qml|Network|Core)\.so\.6|lib(GLX|OpenGL)\.so\.0|libseccomp\.so\.2|libsystemd\.so\.0|libstdc\+\+\.so\.6|libm\.so\.6|libgcc_s\.so\.1|libc\.so\.6|ld-linux-x86-64\.so\.2)$'
verify_elf "$worker" pie "$qt_allowed" libseccomp.so.2
needed_libraries "$worker" | grep -Fx libxkbcommon.so.0 >/dev/null || fail "omarchy-plugin-qml-worker omits required DT_NEEDED libxkbcommon.so.0"
verify_elf "$bridge" shared "$bridge_allowed" libQt6Qml.so.6
needed_libraries "$bridge" | grep -Fx libseccomp.so.2 >/dev/null || fail "libomarchy-plugin-host-bridge.so omits required DT_NEEDED libseccomp.so.2"
needed_libraries "$bridge" | grep -Fx libsystemd.so.0 >/dev/null || fail "libomarchy-plugin-host-bridge.so omits required DT_NEEDED libsystemd.so.0"

python -m json.tool "$root/policy/builtin-capabilities-v1.json" >/dev/null

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME=none \
  QSG_RHI_BACKEND=software \
  /usr/lib/qt6/bin/qml -I "$root/qml" "$script_dir/ModuleProbe.qml" >/dev/null

echo "secure plugin package verification passed: $root"
