echo "Add the agents widget to the bar"

# The widget is now in the default layout. It draws nothing until a provider
# reports usage — Panel.qml is `visible: providers.length > 0`, and Main.qml
# only counts a provider that is enabled *and* has recorded prompts, sessions,
# active days, or a rate limit. So adding it to every existing bar is free:
# machines without Claude Code or Codex never see it.

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

    # Respect a bar the user already curated: only place the widget when it is
    # absent from every section, never a second copy.
    if has_widget("omarchy.agents") then
      .
    else
      .bar.layout.right |= insert_after("omarchy.tray"; { id: "omarchy.agents" })
    end
  ' "$config_file" >"$tmp" && mv "$tmp" "$config_file" || rm -f "$tmp"
fi
