echo "Show hostname in Starship over SSH"

starship_config="$HOME/.config/starship.toml"
old_format_pattern='^[[:space:]]*format = "\[\$directory\$git_branch\$git_status\]\(\$style\)\$character"$'

if [[ -f "$starship_config" ]] && grep -Eq "$old_format_pattern" "$starship_config" && ! grep -q '^\[hostname\]' "$starship_config"; then
  tmp=$(mktemp)
  awk '
    /^[[:space:]]*format = "\[\$directory\$git_branch\$git_status\]\(\$style\)\$character"$/ && !updated {
      print "format = \"[$hostname$directory$git_branch$git_status]($style)$character\""
      updated = 1
      next
    }
    { print }
  ' "$starship_config" >"$tmp" && mv "$tmp" "$starship_config"

  cat >>"$starship_config" <<'EOF'

[hostname]
ssh_only = true
format = '[$hostname]($style) '
EOF
fi
