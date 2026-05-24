echo "Place the system update indicator next to weather in the bar"

config_file="$HOME/.config/omarchy/shell.json"

if [[ -s $config_file ]] && omarchy-cmd-present jq; then
  tmp=$(mktemp)
  jq '
    def entry_id:
      if type == "string" then
        .
      elif type == "object" then
        (.id // "")
      else
        ""
      end;

    def entry_index($id):
      [range(0; length) as $i | select((.[$i] | entry_id) == $id) | $i][0];

    def place_update_after_weather:
      if type != "array" then
        .
      else
        (entry_index("omarchy.weather")) as $weather_index |
        (entry_index("omarchy.indicators")) as $indicators_index |
        (entry_index("omarchy.system-update")) as $update_index |
        if $weather_index == null or $indicators_index == null or $update_index == null then
          .
        elif $weather_index < $indicators_index and $indicators_index < $update_index then
          . as $entries |
          ($entries[$update_index]) as $update_entry |
          ($entries | del(.[$update_index])) as $without_update |
          ($without_update | entry_index("omarchy.weather")) as $new_weather_index |
          $without_update[0:$new_weather_index + 1] + [$update_entry] + $without_update[$new_weather_index + 1:]
        else
          .
        end
      end;

    .bar.layout.center |= place_update_after_weather
  ' "$config_file" >"$tmp" && mv "$tmp" "$config_file" || rm -f "$tmp"
fi
