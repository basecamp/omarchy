echo "Tighten browser managed-policy directory permissions"

# The policy directories used to be world-writable so omarchy-theme-set-browser
# could write color.json as the user. That let any local user or process drop
# arbitrary managed policies into a root-owned browser directory. Restore the
# default 0755 and hand the user ownership of the single file they need to
# update instead.
policy_dirs="${OMARCHY_BROWSER_POLICY_DIRS:-/etc/chromium/policies/managed
/etc/opt/chrome/policies/managed
/etc/opt/edge/policies/managed
/etc/brave/policies/managed}"

while IFS= read -r policy_dir; do
  [[ -d $policy_dir ]] || continue

  if [[ $(stat -c %a "$policy_dir") != "755" ]]; then
    sudo chmod 755 "$policy_dir"
  fi

  if [[ -f $policy_dir/color.json ]]; then
    # Only repair files still owned by root; another user may have already
    # claimed ownership, and that is the intended end state.
    if [[ $(stat -c %U "$policy_dir/color.json") == "root" ]]; then
      sudo chown "$USER:" "$policy_dir/color.json"
    fi
  else
    # Without write access to the directory, omarchy-theme-set-browser can only
    # update an existing color.json, so make sure the file is present.
    printf '%s\n' '{"BrowserThemeColor": "#1c2027", "BrowserColorScheme": "device"}' |
      sudo tee "$policy_dir/color.json" >/dev/null
    sudo chown "$USER:" "$policy_dir/color.json"
  fi
done <<<"$policy_dirs"
