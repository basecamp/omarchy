echo "Make Herdr follow the Omarchy terminal palette"

config_file="${HERDR_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml}"

# New installs already receive theme.name = "terminal" from the shipped config,
# but the first Herdr migration deliberately kept configs from standalone
# installs. Move those existing configs onto the same integration once, without
# replacing any of their keybindings, UI settings, or other preferences.
[[ -f $config_file ]] || exit 0

tmp=$(mktemp)

awk '
  function section(line) {
    return line ~ /^[[:space:]]*\[[^][]+\][[:space:]]*(#.*)?$/
  }

  function theme_section(line) {
    return line ~ /^[[:space:]]*\[theme\][[:space:]]*(#.*)?$/
  }

  function add_name_if_missing() {
    if (in_theme && !wrote_name) {
      print "name = \"terminal\""
      wrote_name = 1
    }
  }

  section($0) {
    add_name_if_missing()
    in_theme = theme_section($0)
    if (in_theme) {
      saw_theme = 1
      wrote_name = 0
    }
    print
    next
  }

  in_theme && /^[[:space:]]*name[[:space:]]*=/ {
    if (!wrote_name) {
      print "name = \"terminal\""
      wrote_name = 1
    }
    next
  }

  { print }

  END {
    add_name_if_missing()
    if (!saw_theme) {
      if (NR) print ""
      print "[theme]"
      print "name = \"terminal\""
    }
  }
' "$config_file" >"$tmp"

if cmp -s "$tmp" "$config_file"; then
  rm -f "$tmp"
  exit 0
fi

# Do not turn a hand-edited but usable config into one Herdr refuses to load.
# HERDR_CONFIG_PATH also keeps this validation isolated from the running server.
if ! HERDR_CONFIG_PATH="$tmp" herdr config check >/dev/null; then
  echo "Could not update $config_file; the generated Herdr config did not validate." >&2
  rm -f "$tmp"
  exit 0
fi

backup="$config_file.bak.$(date +%s)"
cp -p "$config_file" "$backup"

# Write through the path so configs linked from a dotfiles repository keep the
# same symlink and target.
cat "$tmp" >"$config_file"
rm -f "$tmp"

echo "Set Herdr to follow Omarchy themes. Saved backup as $backup."
if ! omarchy-restart-herdr; then
  echo "Could not reload Herdr; the new theme will apply the next time Herdr starts." >&2
fi
