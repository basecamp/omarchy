echo "Ensure interactive shell check is at the top of .bashrc"

BASHRC="$HOME/.bashrc"

if [ -f "$BASHRC" ] && ! grep -q '\[\[ $- != \*i\* \]\] && return' "$BASHRC"; then
  sed -i '1i# If not running interactively, don'\''t do anything (leave this at the top of this file)\n[[ $- != *i* ]] && return\n' "$BASHRC"
fi
