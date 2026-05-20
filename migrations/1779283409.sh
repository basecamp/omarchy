echo "Add Night Light to the default bar indicator list"

config_file="$HOME/.config/omarchy/shell.json"

if [[ -f $config_file ]] && omarchy-cmd-present jq; then
  tmp=$(mktemp)
  jq '
    def indicator_id:
      if type == "string" then
        .
      elif type == "object" then
        (.id // "")
      else
        ""
      end;

    def has_indicator($id):
      any(.[]?; indicator_id == $id);

    def indicator_index($id):
      [range(0; length) as $i | select((.[$i] | indicator_id) == $id) | $i][0];

    def nightlight_entry:
      if any(.[]?; type == "object") then
        { id: "nightlight" }
      else
        "nightlight"
      end;

    def add_nightlight:
      if type != "array" or has_indicator("nightlight") then
        .
      else
        (indicator_index("dnd")) as $dnd_index |
        if $dnd_index == null then
          .
        else
          .[0:$dnd_index + 1] + [nightlight_entry] + .[$dnd_index + 1:]
        end
      end;

    .bar.layout |= (
      if type == "object" then
        with_entries(
          .value |= (
            if type == "array" then
              map(
                if type == "object" and .id == "indicators" then
                  if (.items | type) == "array" then
                    .items |= add_nightlight
                  elif (.indicators | type) == "array" then
                    .indicators |= add_nightlight
                  else
                    .
                  end
                else
                  .
                end
              )
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
