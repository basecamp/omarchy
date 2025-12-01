echo "Ensure config/uwsm/default uses generic terminal exec"

sed -i 's/export TERMINAL=.*/export TERMINAL=xdg-terminal-exec/' ~/.config/uwsm/default
