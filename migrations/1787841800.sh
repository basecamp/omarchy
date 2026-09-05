echo "Add longer idle timeouts for AC power"

# Existing shell.json files are canonical and are not deep-merged with new
# defaults. Users still on the stock 150/300 pair get the shipped AC profile
# (5 min screensaver, 30 min lock). Anyone who already changed idle timings,
# or already set idle.ac, is left alone.

config_file="$HOME/.config/omarchy/shell.json"

[[ -s $config_file ]] || exit 0
omarchy-cmd-present jq || exit 0
jq -e . "$config_file" >/dev/null 2>&1 || exit 0

if ! jq -e '
  (.idle | type == "object" or .idle == null) and
  ((.idle // {}) | has("ac") | not) and
  ((.idle.screensaver // 150) == 150) and
  ((.idle.lock // 300) == 300)
' "$config_file" >/dev/null; then
  exit 0
fi

tmp=$(mktemp)
jq '
  .idle = ((.idle // { screensaver: 150, lock: 300 }) + {
    ac: { screensaver: 300, lock: 1800 }
  })
' "$config_file" >"$tmp" && mv "$tmp" "$config_file" || rm -f "$tmp"
