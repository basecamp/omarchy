# qemu-user-static-binfmt registers its interpreters with flags FP. Docker
# buildx cross-arch builds run emulated-architecture containers where setuid
# binaries (e.g. sudo) need the C flag to keep their credentials under QEMU,
# and O so the interpreter works against a container whose rootfs differs
# from the host's. Override with OCF, derived from the package's own
# registrations so any architectures it adds stay covered.
binfmt_source_dir="${OMARCHY_BINFMT_SOURCE_DIR:-/usr/lib/binfmt.d}"
binfmt_dir="${OMARCHY_BINFMT_DIR:-/etc/binfmt.d}"

mkdir -p "$binfmt_dir"
for conf in "$binfmt_source_dir"/qemu-*-static.conf; do
  [[ -e $conf ]] || continue
  sed -E 's/:[A-Za-z]*$/:OCF/' "$conf" >"$binfmt_dir/$(basename "$conf")"
done
