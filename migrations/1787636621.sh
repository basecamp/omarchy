echo "Add the snippets widget to the bar"

# Same shape as the migration that added omarchy.agents: only place the
# widget when it is absent from every section (a bar the user already
# curated -- including one where they moved or removed it themselves after
# an earlier run of this migration -- is left alone), and anchor it right
# after the tray so it lands in the same spot a fresh install ships it in.

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

    if has_widget("omarchy.snippets") then
      .
    else
      .bar.layout.right |= insert_after("omarchy.tray"; { id: "omarchy.snippets" })
    end
  ' "$config_file" >"$tmp" && mv "$tmp" "$config_file" || rm -f "$tmp"
fi
