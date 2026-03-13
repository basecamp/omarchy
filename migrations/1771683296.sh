echo "Migrate suspend toggle from opt-in to opt-out"

SUSPEND_ON=~/.local/state/omarchy/toggles/suspend-on
SUSPEND_OFF=~/.local/state/omarchy/toggles/suspend-off

if [[ -f $SUSPEND_ON ]]; then
  # User had suspend enabled, remove old file (suspend is now on by default)
  rm -f $SUSPEND_ON
else
  # User had suspend disabled, create opt-out file to preserve their choice
  mkdir -p "$(dirname $SUSPEND_OFF)"
  touch $SUSPEND_OFF
fi
