# Default OMARCHY_PATH for non-install shells. install.sh overrides this
# during the install flow to point at the checkout under
# $HOME/.local/share/omarchy when running in script-install (boot.sh) mode.
# omarchy-dev-link (Chunk 4) manages a symlink at /usr/share/omarchy that
# points at a local checkout when active.
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

# Convenience: prepend Omarchy's user-installable bin to PATH if it exists.
# (Mainly relevant for the script-install path; /usr/bin is already on PATH
# for the package-install path.)
case ":$PATH:" in
  *":$OMARCHY_PATH/bin:"*) ;;
  *) [ -d "$OMARCHY_PATH/bin" ] && export PATH="$OMARCHY_PATH/bin:$PATH" ;;
esac
