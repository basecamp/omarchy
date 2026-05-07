echo "Drop vrr,1 from default monitor line as it creates a small lag"

MONITORS_CONF=~/.config/hypr/monitors.conf

if [[ -f $MONITORS_CONF ]]; then
  sed -i 's/^monitor=,preferred,auto,auto,vrr,1$/monitor=,preferred,auto,auto/' "$MONITORS_CONF"
fi
