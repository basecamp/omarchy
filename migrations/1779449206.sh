echo "Use inline Omarchy editor launcher for terminal EDITOR"

if [[ -f ~/.config/uwsm/default ]]; then
  if grep -q '^export EDITOR=omarchy-launch-editor$' ~/.config/uwsm/default; then
    sed -i 's|^export EDITOR=omarchy-launch-editor$|export EDITOR="omarchy-launch-editor --inline"|' ~/.config/uwsm/default
  elif ! grep -q '^export EDITOR=' ~/.config/uwsm/default; then
    printf '\n# Used by terminal programs to open files with the selected Omarchy default editor\nexport EDITOR="omarchy-launch-editor --inline"\n' >>~/.config/uwsm/default
  fi
else
  omarchy-refresh-config uwsm/default
fi
