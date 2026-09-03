echo "Install Discovery and add its first-party panel"

omarchy-pkg-add omarchy-discovery

config_file="$HOME/.config/omarchy/shell.json"

if [[ -s $config_file ]]; then
  tmp=$(mktemp)
  jq '
    def entry_id:
      if type == "string" then .
      elif type == "object" then (.id // "")
      else ""
      end;

    def rename_discovery:
      if . == "io.github.tcballard.plugin-workbench" or . == "io.github.tcballard.discovery" or . == "omarchy.plugin-workbench" then
        "omarchy.discovery"
      elif type == "object" and (.id == "io.github.tcballard.plugin-workbench" or .id == "io.github.tcballard.discovery" or .id == "omarchy.plugin-workbench") then
        .id = "omarchy.discovery"
      else
        .
      end;

    def deduplicate_entries:
      reduce .[] as $entry (
        [];
        if any(.[]; entry_id == ($entry | entry_id)) then . else . + [$entry] end
      );

    def has_widget($id):
      [(.bar.layout // {}) | to_entries[] | .value | select(type == "array") | .[] | entry_id]
        | any(. == $id);

    def insert_after($anchor; $entry):
      if type != "array" then
        [$entry]
      else
        ([range(0; length) as $i | select((.[$i] | entry_id) == $anchor) | $i][0]) as $anchor_index |
        if $anchor_index == null then
          [$entry] + .
        else
          .[0:$anchor_index + 1] + [$entry] + .[$anchor_index + 1:]
        end
      end;

    (if (.bar.layout? | type) == "object" then
      .bar.layout |= map_values(if type == "array" then map(rename_discovery) | deduplicate_entries else . end)
    else . end)
    | (if has_widget("omarchy.discovery") then
        .
      else
        .bar.layout.right |= insert_after("omarchy.agents"; { id: "omarchy.discovery" })
      end)
    | (if (.disabledPlugins? | type) == "array" then
        .disabledPlugins |= (map(rename_discovery) | unique)
      else . end)
    | (if (.plugins? | type) == "array" then
        .plugins |= map(select((.id // "") != "io.github.tcballard.plugin-workbench" and (.id // "") != "io.github.tcballard.discovery"))
      else . end)
  ' "$config_file" >"$tmp" && mv "$tmp" "$config_file" || rm -f "$tmp"
fi
