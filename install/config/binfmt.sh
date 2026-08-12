# qemu-user-static-binfmt registers its interpreters with flags FP. Docker
# buildx cross-arch builds run emulated-architecture containers where setuid
# binaries (e.g. sudo) need the C flag to keep their credentials under QEMU,
# and O so the interpreter works against a container whose rootfs differs
# from the host's. Override with OCF, derived from the package's own
# registrations so any architectures it adds stay covered.
mkdir -p /etc/binfmt.d
for conf in /usr/lib/binfmt.d/qemu-*-static.conf; do
  sed -E 's/:[A-Za-z]*$/:OCF/' "$conf" >"/etc/binfmt.d/$(basename "$conf")"
done
