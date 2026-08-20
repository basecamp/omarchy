echo "Give herdr agent status indicators a distinct glyph per state"

config="$HOME/.config/herdr/config.toml"
comment='# Distinct glyphs per state, so working and done read on every theme.'

[[ -f $config ]] || exit 0

# Leave a config that already chose a value alone, indented or not
if grep -qE '^[[:space:]]*status_indicators[[:space:]]*=' "$config"; then
  exit 0
fi

if grep -qE '^[[:space:]]*\[ui\][[:space:]]*(#.*)?$' "$config"; then
  awk -v comment="$comment" '
    { print }
    !inserted && /^[[:space:]]*\[ui\][[:space:]]*(#.*)?$/ {
      print ""
      print comment
      print "status_indicators = \"symbols\""
      inserted = 1
    }
  ' "$config" >"$config.omarchy-new"
  mv "$config.omarchy-new" "$config"
else
  printf '\n[ui]\n%s\nstatus_indicators = "symbols"\n' "$comment" >>"$config"
fi

omarchy-restart-herdr
