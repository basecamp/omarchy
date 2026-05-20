echo "Rename the default Calendar bar widget to Daytime"

config_file="$HOME/.config/omarchy/shell.json"

if [[ -f $config_file ]] && omarchy-cmd-present jq; then
  tmp=$(mktemp)
  jq '
    def update_daytime_entry:
      if type == "string" and (. == "calendar" or . == "datetime") then
        "daytime"
      elif type == "object" then
        (
          if .id == "calendar" or .id == "datetime" then
            .id = "daytime"
          else
            .
          end
        ) | (
          if .id == "daytime" and (.formatAlt // "") == "dd MMMM \u0027W\u0027ww yyyy" then
            .formatAlt = "dd MMMM yyyy"
          else
            .
          end
        )
      else
        .
      end;

    .bar.centerAnchor |= if . == "calendar" or . == "datetime" then "daytime" else . end |
    .bar.layout |= (
      if type == "object" then
        with_entries(
          .value |= (
            if type == "array" then
              map(update_daytime_entry)
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
