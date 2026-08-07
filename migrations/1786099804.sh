echo "Rename the model usage widget to agents and prime its data files"

# The widget formerly known as omarchy.model-usage is now omarchy.agents, and
# it no longer scans providers itself: it displays the records that
# omarchy-agent-usage-update writes under ~/.local/state/omarchy/agents/usage/.
# Rename the widget wherever a user's config mentions it — bar layout entries
# keep their settings, a disabled widget stays disabled — then generate the
# records once so the bar doesn't sit empty until the widget's first refresh
# timer, and drop the old scanner's cache directory, which nothing reads
# anymore.

config_file="$HOME/.config/omarchy/shell.json"

if [[ -s $config_file ]]; then
  tmp=$(mktemp)
  jq '
    def rename:
      if . == "omarchy.model-usage" then
        "omarchy.agents"
      elif type == "object" and .id == "omarchy.model-usage" then
        .id = "omarchy.agents"
      else
        .
      end;

    (if (.bar.layout? | type) == "object" then
      .bar.layout |= map_values(if type == "array" then map(rename) else . end)
    else . end)
    | (if (.disabledPlugins? | type) == "array" then
      .disabledPlugins |= map(rename)
    else . end)
  ' "$config_file" >"$tmp" && mv "$tmp" "$config_file" || rm -f "$tmp"
fi

rm -rf "$HOME/.cache/omarchy/model-usage"

omarchy-agent-usage-update || true
