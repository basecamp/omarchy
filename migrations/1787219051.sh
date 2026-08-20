echo "Give herdr agent status indicators a distinct glyph per state"

config="$HOME/.config/herdr/config.toml"
comment='# Distinct glyphs per state, so working and done read on every theme.'

[[ -f $config ]] || exit 0

# Leave a config that already sets it alone, whichever value it chose
grep -q '^status_indicators' "$config" && exit 0

if grep -q '^\[ui\]$' "$config"; then
  awk -v comment="$comment" '
    { print }
    /^\[ui\]$/ && !inserted {
      print ""
      print comment
      print "status_indicators = \"symbols\""
      inserted = 1
    }
  ' "$config" >"$config.omarchy-new" && mv "$config.omarchy-new" "$config"
else
  printf '\n[ui]\n%s\nstatus_indicators = "symbols"\n' "$comment" >>"$config"
fi

omarchy-restart-herdr
