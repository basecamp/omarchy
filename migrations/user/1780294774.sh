echo "Remove leading zero from bar clock date"

config_file="$HOME/.config/omarchy/shell.json"

if [[ -f $config_file ]] && omarchy-cmd-present jq; then
  tmp=$(mktemp)
  jq '
    def update_clock_format:
      if type == "object" and (.id // "") == "omarchy.clock" and (.formatAlt // "") == "dd MMMM \u0027W\u0027ww yyyy" then
        .formatAlt = "d MMMM \u0027W\u0027ww yyyy"
      else
        .
      end;

    .bar.layout |= (
      if type == "object" then
        with_entries(
          .value |= (
            if type == "array" then
              map(update_clock_format)
            else
              .
            end
          )
        )
      else
        .
      end
    )
  ' "$config_file" >"$tmp" && mv "$tmp" "$config_file" || rm -f "$tmp"
fi
