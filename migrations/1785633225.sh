echo "Speed up mouse scrolling in foot"

foot_config="$HOME/.config/foot/foot.ini"

if [[ -f $foot_config ]] && ! grep -q '^multiplier=' "$foot_config"; then
  if grep -qxF '[scrollback]' "$foot_config"; then
    tmp=$(mktemp)
    awk '
      { print }
      !inserted && $0 == "[scrollback]" {
        print "multiplier=7.0"
        inserted = 1
      }
    ' "$foot_config" >"$tmp"
    cat "$tmp" >"$foot_config"
    rm -f "$tmp"
  else
    printf '\n[scrollback]\nmultiplier=7.0\n' >>"$foot_config"
  fi
fi
