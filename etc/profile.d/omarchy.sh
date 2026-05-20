# Default OMARCHY_PATH for non-install shells. install.sh overrides this
# during the install flow to point at the checkout under
# $HOME/.local/share/omarchy when running in script-install (boot.sh) mode.
# omarchy-dev-link (Chunk 4) manages a symlink at /usr/share/omarchy that
# points at a local checkout when active.
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

# Prepend $OMARCHY_PATH/bin if it exists. In normal package mode this is a
# no-op: bins ship to /usr/bin (already on PATH), and /usr/share/omarchy/bin
# doesn't exist. The case that matters is omarchy-dev-link, which makes
# /usr/share/omarchy a symlink to a local checkout; then this prepend lets
# the checkout's bin/omarchy-* override the /usr/bin copies installed by
# the package.
case ":$PATH:" in
  *":$OMARCHY_PATH/bin:"*) ;;
  *) [ -d "$OMARCHY_PATH/bin" ] && export PATH="$OMARCHY_PATH/bin:$PATH" ;;
esac
