echo "Move the bar indicators to the left of the clock"

config_file="$HOME/.config/omarchy/shell.json"

if [[ -s $config_file ]]; then
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

    def place_indicators_before_clock:
      if type != "array" then
        .
      else
        (entry_index("omarchy.clock")) as $clock_index |
        (entry_index("omarchy.indicators")) as $indicators_index |
        if $clock_index == null or $indicators_index == null or $indicators_index < $clock_index then
          .
        else
          . as $entries |
          ($entries[$indicators_index]) as $indicators_entry |
          ($entries | del(.[$indicators_index])) as $without_indicators |
          ($without_indicators | entry_index("omarchy.clock")) as $new_clock_index |
          $without_indicators[0:$new_clock_index] + [$indicators_entry] + $without_indicators[$new_clock_index:]
        end
      end;

    .bar.layout.center |= place_indicators_before_clock
  ' "$config_file" >"$tmp" && mv "$tmp" "$config_file" || rm -f "$tmp"
fi

omarchy-restart-shell
