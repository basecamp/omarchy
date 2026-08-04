echo "Remove the tmux alert hooks and its bar indicator"

tmux_config="$HOME/.config/tmux/tmux.conf"

# Drop only the hooks Omarchy installed, wherever the migrations that wrote
# them left them, and only the blank run around what goes: every other line
# comes through untouched.
if [[ -f $tmux_config ]]; then
  tmp=$(mktemp)

  if awk '
    function flush(count,   i) { for (i = 0; i < count; i++) print "" }

    function keep(line) {
      if (dropped) { if (printed && blanks) print "" }
      else flush(blanks)

      blanks = 0
      dropped = 0
      printed = 1
      print line
    }

    # The heading only belongs to the block when a removed hook follows it.
    /^[[:space:]]*# Alerts$/ && header == "" { header = $0; next }

    /^[[:space:]]*set-hook -g alert-(bell|activity|silence) .*omarchy\.indicators refresh/ ||
    /^[[:space:]]*set-hook -g (after-select-window|client-session-changed|client-focus-(in|out))(\[[0-9]+\])? .*(omarchy-tmux-alert track|omarchy\.indicators refresh)/ {
      header = ""
      dropped = 1
      next
    }

    /^[[:space:]]*$/ {
      if (header != "") { keep(header); header = "" }
      blanks++
      next
    }

    {
      if (header != "") { keep(header); header = "" }
      keep($0)
    }

    END {
      if (header != "") keep(header)
      if (!dropped) flush(blanks)
    }
  ' "$tmux_config" >"$tmp"; then
    if ! cmp -s "$tmp" "$tmux_config"; then
      # Write through the path instead of replacing it, so a tmux.conf
      # symlinked out of a dotfiles repo keeps pointing where it pointed.
      cat "$tmp" >"$tmux_config"
      omarchy-restart-tmux
    fi
  else
    echo "Could not rewrite $tmux_config; remove the tmux alert hooks by hand."
  fi

  rm -f "$tmp"
fi

# A running server keeps its hooks as options, so sourcing a config that no
# longer sets them leaves every one of them firing at the deleted command.
# Unset by the exact name and index tmux reports, which leaves hooks the user
# added at other indexes alone.
if tmux has-session 2>/dev/null; then
  while read -r hook; do
    [[ -n $hook ]] || continue
    tmux set-hook -gu "$hook" 2>/dev/null || true
  done < <(tmux show-hooks -g 2>/dev/null |
    awk '$0 ~ /omarchy-tmux-alert|omarchy\.indicators refresh/ { print $1 }')

  # The removed track subcommand stamped this on every window it saw.
  while read -r window; do
    [[ -n $window ]] || continue
    tmux set-option -wqu -t "$window" @omarchy_unfocused_activity 2>/dev/null || true
  done < <(tmux list-windows -a -F '#{window_id}' 2>/dev/null)
fi

# Only a hand-picked indicator list names TmuxAlert; the default list lives in
# the widget. An emptied list would read as "show them all", so a widget that
# has nothing left to show goes with it.
config_file="$HOME/.config/omarchy/shell.json"

if [[ -s $config_file ]] && grep -q 'TmuxAlert' "$config_file"; then
  tmp=$(mktemp)

  if jq '
    def entry_id:
      if type == "string" then . elif type == "object" then (.id // "") else "" end;

    def without_tmux_alert: map(select(entry_id != "TmuxAlert"));

    def stripped($key):
      if (.[$key] | type) == "array" then .[$key] |= without_tmux_alert else . end;

    # The list the widget actually reads: "indicators" is the older spelling of
    # "items", and either one empty means "show the default set".
    def picked:
      if (.items | type) == "array" and (.items | length) > 0 then .items
      elif (.indicators | type) == "array" and (.indicators | length) > 0 then .indicators
      else null end;

    def cleaned:
      if type == "object" and .id == "omarchy.indicators" then stripped("items") | stripped("indicators") else . end;

    def emptied:
      type == "object" and .id == "omarchy.indicators" and
      picked != null and (cleaned | picked) == null;

    walk(if type == "array" then map(select(emptied | not)) | map(cleaned) else . end)
  ' "$config_file" >"$tmp"; then
    cat "$tmp" >"$config_file"
  else
    echo "Could not rewrite $config_file; remove the TmuxAlert indicator by hand."
  fi

  rm -f "$tmp"
fi
