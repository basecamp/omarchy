echo "Update Pi CLI wrapper package"

pi_bin="$HOME/.local/bin/pi"

if [[ -f $pi_bin ]] && grep -q '^package="@mariozechner/pi-coding-agent"$' "$pi_bin"; then
  sed -i 's|^package="@mariozechner/pi-coding-agent"$|package="@earendil-works/pi-coding-agent"|' "$pi_bin"
fi
