# Setup default work directory (and tries)
mkdir -p "$HOME/Work"
mkdir -p "$HOME/Work/tries"

cat >"$HOME/Work/.mise.toml" <<'EOF'
[env]
_.path = "{{ cwd }}/bin"
EOF

mise trust ~/Work/.mise.toml

# Offline installs unpack the Node tarball bundled by the ISO: from
# /opt/packages in the ISO chroot, or from the copy staged in provisioning state when
# omarchy-provision-owner finalizes the user at first boot.
case ${OMARCHY_SETUP_CONTEXT:-runtime} in
  iso-chroot) NODE_PACKAGE_DIR=/opt/packages ;;
  provision-owner) NODE_PACKAGE_DIR=/var/lib/omarchy/provisioning/packages ;;
  *) NODE_PACKAGE_DIR="" ;;
esac

if [[ -n $NODE_PACKAGE_DIR ]]; then
  NODE_TARBALL=$(find "$NODE_PACKAGE_DIR" -name "node-v*-linux-x64.tar.gz" -type f 2>/dev/null | head -n1)
  if [[ -z $NODE_TARBALL ]]; then
    if [[ ${OMARCHY_SETUP_CONTEXT:-} == "provision-owner" ]]; then
      # A factory snapshot predating the bundled tarball may not have it staged.
      # Leave Node to the network rather than failing the whole first boot.
      echo "Warning: no bundled Node.js tarball in $NODE_PACKAGE_DIR; trying the network" >&2
      mise use -g node@latest || echo "Warning: Node.js install deferred (no network)" >&2
    else
      echo "Error: bundled Node.js tarball missing from $NODE_PACKAGE_DIR" >&2
      exit 1
    fi
  else
    NODE_VERSION=$(basename "$NODE_TARBALL" | sed 's/node-v\(.*\)-linux-x64.tar.gz/\1/')
    NODE_INSTALL_DIR="$HOME/.local/share/mise/installs/node/$NODE_VERSION"

    mkdir -p "$NODE_INSTALL_DIR"
    tar -xzf "$NODE_TARBALL" --strip-components=1 -C "$NODE_INSTALL_DIR"
    mise use -g node@"$NODE_VERSION"
  fi
else
  mise use -g node@latest
fi
