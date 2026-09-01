#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 <output-directory>" >&2
  exit 64
}

if (( $# != 1 )); then
  usage
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
runtime_source=$(realpath -e -- "$script_dir/../..")
repository=$(git -C "$runtime_source" rev-parse --show-toplevel)
output_directory=$1

if ! git -C "$repository" diff --quiet -- native/plugin-runtime ||
  ! git -C "$repository" diff --cached --quiet -- native/plugin-runtime ||
  [[ -n $(git -C "$repository" ls-files --others --exclude-standard -- native/plugin-runtime) ]]; then
  echo "secure plugin package builds require a committed native/plugin-runtime tree" >&2
  exit 1
fi

mkdir -p -- "$output_directory"
output_directory=$(realpath -e -- "$output_directory")
[[ $output_directory != "/" ]] || {
  echo "refusing to write package output at the filesystem root" >&2
  exit 1
}

commit=$(git -C "$repository" rev-parse HEAD)
source_date_epoch=$(git -C "$repository" show -s --format=%ct "$commit")
context=$(mktemp -d)
cleanup() {
  rm -rf -- "$context"
}
trap cleanup EXIT

version=0.1.0
source_archive="$context/plugin-runtime-${version}.tar.gz"
git -C "$repository" archive --format=tar.gz \
  --prefix="plugin-runtime-${version}/" \
  --output="$source_archive" "$commit:native/plugin-runtime"

bsdtar -xf "$source_archive" -C "$context"
dependency_contract="$context/runtime-dependencies-v1.txt"
cp -- "$context/plugin-runtime-${version}/packaging/runtime-dependencies-v1.txt" \
  "$dependency_contract"
cp -- "$script_dir/PKGBUILD" "$context/PKGBUILD"

export OMARCHY_PLUGIN_SOURCE_SHA256
export OMARCHY_PLUGIN_DEPENDENCIES_SHA256
export SOURCE_DATE_EPOCH="$source_date_epoch"
export PACKAGER="Omarchy package build <noreply@omarchy.org>"
OMARCHY_PLUGIN_SOURCE_SHA256=$(sha256sum "$source_archive")
OMARCHY_PLUGIN_SOURCE_SHA256=${OMARCHY_PLUGIN_SOURCE_SHA256%% *}
OMARCHY_PLUGIN_DEPENDENCIES_SHA256=$(sha256sum "$dependency_contract")
OMARCHY_PLUGIN_DEPENDENCIES_SHA256=${OMARCHY_PLUGIN_DEPENDENCIES_SHA256%% *}

makepkg --dir "$context" --cleanbuild --force --nodeps --noconfirm

mapfile -t packages < <(find "$context" -maxdepth 1 -type f \
  -name 'omarchy-plugin-security-*.pkg.tar.zst' -print)
(( ${#packages[@]} == 1 )) || {
  echo "package build did not produce exactly one archive" >&2
  exit 1
}

"$script_dir/verify-archive-metadata.sh" "${packages[0]}" "$version"

package_name=$(basename -- "${packages[0]}")
[[ ! -e $output_directory/$package_name ]] || {
  echo "package output already exists: $output_directory/$package_name" >&2
  exit 1
}
install -m 644 -- "${packages[0]}" "$output_directory/$package_name"
echo "$output_directory/$package_name"
