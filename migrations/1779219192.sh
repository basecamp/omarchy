echo "Move default editor selection to ~/.local/state/omarchy/defaults/editor"

editor=$(sed -n 's/^export EDITOR=//p' ~/.config/uwsm/default 2>/dev/null | head -n 1)

if [[ -z $editor || $editor == "omarchy-launch-editor" ]]; then
  editor="nvim"
fi

mkdir -p "$HOME/.local/state/omarchy/defaults"

if [[ ! -f $HOME/.local/state/omarchy/defaults/editor ]]; then
  printf '%s\n' "$editor" >"$HOME/.local/state/omarchy/defaults/editor"
fi

if [[ -f ~/.config/uwsm/default ]]; then
  if grep -q '^export EDITOR=' ~/.config/uwsm/default; then
    sed -i 's|^export EDITOR=.*|export EDITOR=omarchy-launch-editor|' ~/.config/uwsm/default
  else
    printf '\n# Used by terminal programs to open files with the selected Omarchy default editor\nexport EDITOR=omarchy-launch-editor\n' >>~/.config/uwsm/default
  fi
else
  omarchy-refresh-config uwsm/default
fi
