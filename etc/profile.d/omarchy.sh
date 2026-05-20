[ -f /etc/omarchy.conf ] && . /etc/omarchy.conf
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

# omarchy-dev-link: prepend checkout bin/ so it shadows /usr/bin/omarchy-*.
case ":$PATH:" in
  *":$OMARCHY_PATH/bin:"*) ;;
  *) [ -d "$OMARCHY_PATH/bin" ] && export PATH="$OMARCHY_PATH/bin:$PATH" ;;
esac
