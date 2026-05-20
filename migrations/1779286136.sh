echo "Replace the old Stay Awake bar widget with the Stay Awake indicator"

config_file="$HOME/.config/omarchy/shell.json"

if [[ -f $config_file ]] && omarchy-cmd-present jq; then
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

    def stay_awake_entry:
      if any(.[]?; type == "object") then
        { id: "stayAwake" }
      else
        "stayAwake"
      end;

    def add_stay_awake:
      if type != "array" or has_indicator("stayAwake") then
        .
      else
        . + [stay_awake_entry]
      end;

    def update_indicators:
      if type == "object" and .id == "indicators" then
        if (.items | type) == "array" then
          .items |= add_stay_awake
        elif (.indicators | type) == "array" then
          .indicators |= add_stay_awake
        else
          .items = ["stayAwake"]
        end
      elif type == "string" and . == "indicators" then
        { id: "indicators", items: ["stayAwake"] }
      else
        .
      end;

    def replace_idle_when_no_indicators:
      reduce .[] as $entry (
        { rows: [], inserted: false };
        if ($entry | entry_id) == "idleInhibitor" then
          if .inserted then
            .
          else
            .rows += [{ id: "indicators", items: ["stayAwake"] }] | .inserted = true
          end
        else
          .rows += [$entry]
        end
      ) | .rows;

    def replace_idle_inhibitor($has_indicators):
      if type != "array" then
        .
      elif $has_indicators then
        [ .[] | select(entry_id != "idleInhibitor") | update_indicators ]
      else
        replace_idle_when_no_indicators
      end;

    (.bar.layout | [ .[]?[]? | select(entry_id == "indicators") ] | length > 0) as $has_indicators |
    .bar.layout |= (
      if type == "object" then
        with_entries(.value |= replace_idle_inhibitor($has_indicators))
      else
        .
      end
    )
  ' "$config_file" >"$tmp" && mv "$tmp" "$config_file" || rm -f "$tmp"
fi
