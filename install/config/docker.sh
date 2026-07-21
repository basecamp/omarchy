usermod -aG docker "$OMARCHY_INSTALL_USER"

# Ensure sudo works in cross-platform Docker image builds
for src in /usr/lib/binfmt.d/qemu-*-static.conf; do
  dst="/etc/binfmt.d/$(basename "$src")"
  install -Dm644 "$src" "$dst"
  sed -i 's/:FP$/:OCF/' "$dst"
done
