# Source /etc/omarchy.conf first so dev-link or other system overrides can
# pre-set OMARCHY_PATH (and anything else) before the defaults run.
# install.sh's script-mode export still wins because /etc/omarchy.conf uses
# the same :- guard.
[ -f /etc/omarchy.conf ] && . /etc/omarchy.conf
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

# Prepend $OMARCHY_PATH/bin if it exists. In normal package mode this is a
# no-op: bins ship to /usr/bin (already on PATH), and /usr/share/omarchy/bin
# doesn't exist. When omarchy-dev-link is active OMARCHY_PATH points at a
# local checkout, whose bin/ then overrides the /usr/bin copies.
case ":$PATH:" in
  *":$OMARCHY_PATH/bin:"*) ;;
  *) [ -d "$OMARCHY_PATH/bin" ] && export PATH="$OMARCHY_PATH/bin:$PATH" ;;
esac
