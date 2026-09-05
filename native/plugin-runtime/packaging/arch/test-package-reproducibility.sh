#!/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
scratch=$(mktemp -d)
cleanup() {
  rm -rf -- "$scratch"
}
trap cleanup EXIT

mkdir "$scratch/first" "$scratch/second"
"$script_dir/build-package.sh" "$scratch/first"
"$script_dir/build-package.sh" "$scratch/second"
mapfile -t first_packages < <(find "$scratch/first" -maxdepth 1 -type f -name '*.pkg.tar.zst')
mapfile -t second_packages < <(find "$scratch/second" -maxdepth 1 -type f -name '*.pkg.tar.zst')
(( ${#first_packages[@]} == 1 && ${#second_packages[@]} == 1 )) || {
  echo "clean builds did not each produce exactly one package" >&2
  exit 1
}
first=${first_packages[0]}
second=${second_packages[0]}

mkdir "$scratch/first-payload" "$scratch/second-payload"
bsdtar -xf "$first" -C "$scratch/first-payload" \
  --exclude .BUILDINFO --exclude .MTREE --exclude .PKGINFO
bsdtar -xf "$second" -C "$scratch/second-payload" \
  --exclude .BUILDINFO --exclude .MTREE --exclude .PKGINFO
diff -qr "$scratch/first-payload" "$scratch/second-payload"

cmp <(bsdtar -xOf "$first" .PKGINFO) <(bsdtar -xOf "$second" .PKGINFO)
cmp \
  <(bsdtar -xOf "$first" .BUILDINFO | sed '/^builddir = /d; /^startdir = /d') \
  <(bsdtar -xOf "$second" .BUILDINFO | sed '/^builddir = /d; /^startdir = /d')
cmp \
  <(bsdtar -xOf "$first" .MTREE | gzip -dc | sed '\#^\./\.BUILDINFO #d') \
  <(bsdtar -xOf "$second" .MTREE | gzip -dc | sed '\#^\./\.BUILDINFO #d')

echo "secure plugin package normalized reproducibility passed"
echo "makepkg records its temporary builddir and startdir in .BUILDINFO; outer archives therefore differ"
