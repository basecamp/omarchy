echo "Add the keyboard layout widget to the bar"

# The widget is now in the default layout, sitting just right of the clock. It
# hides itself unless the active keyboard has more than one layout configured,
# so adding it to every existing bar is free: a machine on a single kb_layout
# never sees it.

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
    # absent from every section, never a second copy. A widget the user took off
    # the bar on purpose is listed in disabledPlugins, so leave that alone too.
    if has_widget("omarchy.keyboard-layout")
      or ((.disabledPlugins // []) | any(. == "omarchy.keyboard-layout")) then
      .
    else
      .bar.layout.center |= insert_after("omarchy.clock"; { id: "omarchy.keyboard-layout" })
    end
  ' "$config_file" >"$tmp" && mv "$tmp" "$config_file" || rm -f "$tmp"
fi
