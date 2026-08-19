echo "Remove the unofficial Cursor asdf stub"

stub="$HOME/.local/bin/cursor-agent"
if [[ -f $stub ]] && grep -Fq 'asdf:icholy/asdf-cursor-agent' "$stub"; then
  rm -f "$stub"
fi
