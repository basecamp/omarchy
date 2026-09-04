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
[[ $staging != "/" ]] || fail "staging root must not be the live filesystem"
[[ $staging == /* && $(realpath -e -- "$staging") == "$staging" ]] ||
  fail "staging root path is not canonical"

root=$staging/usr/lib/omarchy/plugin-security/$version
manifest=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/package-manifest-v1.txt

declare -A expected_type expected_mode seen
add_expected() {
  local relative=$1 type=$2 mode=$3
  [[ -z ${expected_type[$relative]+present} ]] ||
    fail "package manifest contains a duplicate member: $relative"
  expected_type[$relative]=$type
  expected_mode[$relative]=$mode
}

for directory in \
  . \
  usr \
  usr/lib \
  usr/lib/omarchy \
  usr/lib/omarchy/plugin-security \
  "usr/lib/omarchy/plugin-security/$version" \
  "usr/lib/omarchy/plugin-security/$version/capabilities.d" \
  "usr/lib/omarchy/plugin-security/$version/commands.d" \
  "usr/lib/omarchy/plugin-security/$version/providers.d"; do
  add_expected "$directory" d 755
done

while read -r mode relative extra; do
  [[ -n $mode && -n $relative && -z ${extra:-} ]] ||
    fail "package manifest contains a malformed row"
  [[ $mode == "644" || $mode == "755" ]] ||
    fail "package manifest contains an unsupported mode: $relative"
  [[ $relative =~ ^[A-Za-z0-9._/-]+$ && $relative != /* &&
     $relative != *//* && $relative != ".." &&
     $relative != ../* && $relative != */../* && $relative != */.. ]] ||
    fail "package manifest contains an unsafe path: $relative"
  package_relative="usr/lib/omarchy/plugin-security/$version/$relative"
  add_expected "$package_relative" f "$mode"
  parent=${package_relative%/*}
  while [[ $parent != "usr/lib/omarchy/plugin-security/$version" ]]; do
    if [[ -z ${expected_type[$parent]+present} ]]; then
      add_expected "$parent" d 755
    fi
    parent=${parent%/*}
  done
done < "$manifest"

tree_listing=$(mktemp)
cleanup_tree_listing() {
  rm -f -- "$tree_listing"
}
trap cleanup_tree_listing EXIT
find -P "$staging" -printf '%P\0%y\0%m\0%U\0%G\0%n\0' >"$tree_listing"
mapfile -d '' tree_fields <"$tree_listing"
(( ${#tree_fields[@]} % 6 == 0 )) || fail "staging tree metadata is incomplete"

for ((index = 0; index < ${#tree_fields[@]}; index += 6)); do
  relative=${tree_fields[index]}
  type=${tree_fields[index + 1]}
  mode=${tree_fields[index + 2]}
  uid=${tree_fields[index + 3]}
  gid=${tree_fields[index + 4]}
  links=${tree_fields[index + 5]}
  [[ -n $relative ]] || relative=.
  [[ -n ${expected_type[$relative]+present} ]] ||
    fail "staging tree contains an unexpected member: $relative"
  [[ $type == "${expected_type[$relative]}" ]] ||
    fail "staging tree member has wrong type: $relative"
  [[ $mode == "${expected_mode[$relative]}" ]] ||
    fail "staging tree member has wrong mode: $relative"
  [[ $uid == "0" && $gid == "0" ]] ||
    fail "staging tree member is not owned by root:root: $relative"
  if [[ $type == "f" && $links != "1" ]]; then
    fail "staging tree file has multiple hard links: $relative"
  fi
  seen[$relative]=1
done

for relative in "${!expected_type[@]}"; do
  [[ -n ${seen[$relative]+present} ]] ||
    fail "staging tree omits required member: $relative"
done

worker=$root/bin/omarchy-plugin-qml-worker
command_executor=$root/bin/omarchy-plugin-command-executor
desktop_opener=$root/bin/omarchy-plugin-desktop-opener
command_policy=$root/commands.d/github-api-v1.policy
command_provider=$root/providers.d/bash-execute.profile
desktop_open_provider=$root/providers.d/external-open-uri-https.profile
bridge=$root/qml/Omarchy/PluginHost/libomarchy-plugin-host-bridge.so
runtime_dependencies=$root/metadata/runtime-dependencies-v1.txt
runtime_paths=$root/metadata/runtime-paths-v1.txt
canonical_worker=/usr/lib/omarchy/plugin-security/$version/bin/omarchy-plugin-qml-worker

[[ $(<"$runtime_paths") == "worker=$canonical_worker" ]] ||
  fail "runtime path contract is not canonical"

expected_dependencies=$(cat <<EOF
bubblewrap
glibc
libgcc
libseccomp
libstdc++
omarchy
qt6-base
qt6-declarative
quickshell
systemd-libs
EOF
)
[[ $(<"$runtime_dependencies") == $expected_dependencies ]] ||
  fail "runtime dependency contract differs from the required Arch package set"

command_contract=$(jq -er '.definitions[] | select(.capability == "bash.execute") | .contractDigest' "$root/metadata/capability-catalog-v1.json") ||
  fail "command capability contract is unavailable"
command_executor_digest=$(sha256sum "$command_executor")
command_executor_digest=${command_executor_digest%% *}
expected_command_provider=$(cat <<EOF
schema=1
adapter-class=bounded-command-execute
contract-digest=$command_contract
abi-version=1
group=command.executor
executable=/usr/lib/omarchy/plugin-security/$version/bin/omarchy-plugin-command-executor
executable-sha256=$command_executor_digest
arg=/usr/lib/omarchy/plugin-security/$version/commands.d
arg=/etc/omarchy/plugin-command-profiles.d
arg=0
invocation-timeout-ms=30000
EOF
)
[[ $(<"$command_provider") == "$expected_command_provider" ]] ||
  fail "command provider profile does not pin the installed executor and capability contract"
desktop_open_contract=$(jq -er '.definitions[] | select(.capability == "external.open-uri.https") | .contractDigest' "$root/metadata/capability-catalog-v1.json") ||
  fail "desktop-open capability contract is unavailable"
desktop_opener_digest=$(sha256sum "$desktop_opener")
desktop_opener_digest=${desktop_opener_digest%% *}
expected_desktop_open_provider=$(cat <<EOF
schema=1
adapter-class=desktop-open-uri
contract-digest=$desktop_open_contract
abi-version=1
group=desktop.open-uri
executable=/usr/lib/omarchy/plugin-security/$version/bin/omarchy-plugin-desktop-opener
executable-sha256=$desktop_opener_digest
invocation-timeout-ms=5000
EOF
)
[[ $(<"$desktop_open_provider") == "$expected_desktop_open_provider" ]] ||
  fail "desktop-open provider profile does not pin the installed opener and capability contract"
if ! jq -e '
  .schemaVersion == 1 and
  .profile == "github-api-v1" and
  .command == "gh" and
  .executable == "/usr/bin/gh" and
  .accountHome == true and
  (.rules | type == "array" and length > 0)
' "$command_policy" >/dev/null; then
  fail "GitHub command policy is invalid"
fi

qt_allowed='^(libQt6(Quick|OpenGL|Gui|Qml|Network|Core)\.so\.6|lib(GLX|OpenGL)\.so\.0|libseccomp\.so\.2|libxkbcommon\.so\.0|libstdc\+\+\.so\.6|libm\.so\.6|libgcc_s\.so\.1|libc\.so\.6)$'
bridge_allowed='^(libQt6(Quick|OpenGL|Gui|Qml|Network|DBus|Core)\.so\.6|lib(GLX|OpenGL)\.so\.0|libseccomp\.so\.2|libsystemd\.so\.0|libstdc\+\+\.so\.6|libm\.so\.6|libgcc_s\.so\.1|libc\.so\.6|ld-linux-x86-64\.so\.2)$'
verify_elf "$worker" pie "$qt_allowed" libseccomp.so.2
verify_elf "$command_executor" pie "$qt_allowed" libQt6Core.so.6
verify_elf "$desktop_opener" pie "$qt_allowed" libQt6Core.so.6
verify_elf "$bridge" shared "$bridge_allowed" libQt6Qml.so.6
needed_libraries "$bridge" | grep -Fx libseccomp.so.2 >/dev/null || fail "libomarchy-plugin-host-bridge.so omits required DT_NEEDED libseccomp.so.2"
needed_libraries "$bridge" | grep -Fx libsystemd.so.0 >/dev/null || fail "libomarchy-plugin-host-bridge.so omits required DT_NEEDED libsystemd.so.0"

expected_bridge_exports=$(cat <<'EOF'
_Z37qml_register_types_Omarchy_PluginHostv
omarchy_plugin_host_worker_path_v1
qt_plugin_instance
qt_plugin_query_metadata_v2
EOF
)
bridge_exports=$(nm -D --defined-only "$bridge" | awk '$2 ~ /^[BDRT]$/ {print $3}' | LC_ALL=C sort)
[[ $bridge_exports == "$expected_bridge_exports" ]] ||
  fail "libomarchy-plugin-host-bridge.so exports an unexpected strong symbol"

if ! worker_contract=$("$worker" --runtime-worker-path 2>/dev/null); then
  fail "worker runtime path contract is unavailable"
fi
[[ $worker_contract == "$canonical_worker" ]] ||
  fail "worker runtime path contract is not canonical"

if ! bridge_contract=$(/usr/bin/python -c '
import ctypes
import sys
bridge = ctypes.CDLL(sys.argv[1])
contract = bridge.omarchy_plugin_host_worker_path_v1
contract.restype = ctypes.c_char_p
value = contract()
if value is None:
    raise RuntimeError("empty bridge worker path contract")
sys.stdout.write(value.decode("ascii"))
' "$bridge" 2>/dev/null); then
  fail "bridge runtime path contract is unavailable"
fi
[[ $bridge_contract == "$canonical_worker" ]] ||
  fail "bridge runtime path contract is not canonical"

set +e
"$worker" >/dev/null 2>&1
worker_status=$?
set -e
(( worker_status == 78 )) || fail "worker does not reject direct execution"
readelf -Ws "$worker" | grep -F '@Qt_6_PRIVATE_API' >/dev/null ||
  fail "touch worker does not expose its current Qt private ABI dependency"

if ! python -m json.tool "$root/policy/builtin-capabilities-v1.json" >/dev/null 2>&1; then
  fail "builtin capability policy is not valid JSON"
fi
if ! jq -e '
  .schemaVersion == 1 and
  .manifestReferencesRequireExactPins == true and
  [.definitions[].capability] == [
    "network.fetch", "external.open-uri.https", "system.observe",
    "device.observe", "device.control", "remote-account.read",
    "remote-account.write", "media.play-stream", "bash.execute"
  ] and
  all(.definitions[];
    .definitionGeneration == 1 and
    (.definitionDigest | test("^[0-9a-f]{64}$")) and
    (.contractDigest | test("^[0-9a-f]{64}$")))
' "$root/metadata/capability-catalog-v1.json" >/dev/null; then
  fail "generated capability catalog is invalid"
fi
while IFS=$'\t' read -r capability definition_digest contract_digest; do
  definition="$root/capabilities.d/$capability.capability"
  grep -Fx "canonical-name=$capability" "$definition" >/dev/null ||
    fail "capability definition name differs from catalog: $capability"
  grep -Fx "definition-digest=$definition_digest" "$definition" >/dev/null ||
    fail "capability definition digest differs from catalog: $capability"
  grep -Fx "contract-digest=$contract_digest" "$definition" >/dev/null ||
    fail "capability contract digest differs from catalog: $capability"
done < <(jq -r '.definitions[] | [.capability, .definitionDigest, .contractDigest] | @tsv' \
  "$root/metadata/capability-catalog-v1.json")

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! /usr/lib/qt6/bin/qmllint -I "$root/qml" "$root"/shell/*.qml \
  >/dev/null 2>&1; then
  fail "installed shell QML syntax validation failed"
fi
if ! QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME=none \
  QSG_RHI_BACKEND=software \
  /usr/lib/qt6/bin/qml -I "$root/qml" "$script_dir/ModuleProbe.qml" >/dev/null; then
  fail "QML module import probe failed"
fi

echo "secure plugin package verification passed: $root"
