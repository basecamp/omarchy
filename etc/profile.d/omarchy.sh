# Default OMARCHY_PATH for non-install shells.
#
# - install.sh sets OMARCHY_PATH to $HOME/.local/share/omarchy during the
#   script-install (boot.sh) flow; that wins because of the :- guards.
# - omarchy-dev-link manages /usr/share/omarchy-dev as a symlink to a local
#   checkout. When present, it shadows the package install for everything
#   that resolves via $OMARCHY_PATH (bin/, default/, shell/, themes/).
# - Otherwise: the package install at /usr/share/omarchy.
if [ -z "${OMARCHY_PATH:-}" ]; then
  if [ -d /usr/share/omarchy-dev ]; then
    export OMARCHY_PATH=/usr/share/omarchy-dev
  else
    export OMARCHY_PATH=/usr/share/omarchy
  fi
fi

# Prepend $OMARCHY_PATH/bin if it exists. In normal package mode this is a
# no-op: bins ship to /usr/bin (already on PATH), and /usr/share/omarchy/bin
# doesn't exist. The case that matters is omarchy-dev-link, which exposes the
# checkout's bin/ at /usr/share/omarchy-dev/bin so it can override the
# /usr/bin copies the package installed.
case ":$PATH:" in
  *":$OMARCHY_PATH/bin:"*) ;;
  *) [ -d "$OMARCHY_PATH/bin" ] && export PATH="$OMARCHY_PATH/bin:$PATH" ;;
esac
