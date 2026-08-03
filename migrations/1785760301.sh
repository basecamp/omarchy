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

  # Restore the default 0755 first; once the directory is no longer
  # world-writable nothing can plant new entries while it is being repaired.
  if [[ $(stat -c %a "$policy_dir") != "755" ]]; then
    sudo chmod 755 "$policy_dir"
  fi

  color_json="$policy_dir/color.json"

  # While the directory was world-writable an attacker could have planted a
  # symlink or FIFO here, and stat, chown, and tee would all follow it.
  # Replace anything that is not a plain regular file.
  if [[ -L $color_json || ! -f $color_json ]]; then
    if [[ -e $color_json || -L $color_json ]]; then
      sudo rm -rf -- "$color_json"
    fi
    # Without write access to the directory, omarchy-theme-set-browser can only
    # update an existing color.json, so make sure the file is present.
    printf '%s\n' '{"BrowserThemeColor": "#1c2027", "BrowserColorScheme": "device"}' |
      sudo tee "$color_json" >/dev/null
    sudo chmod 0644 "$color_json"
    sudo chown "$USER:" "$color_json"
  elif [[ $(stat -c %U "$color_json") == "root" ]]; then
    # Only repair files still owned by root; another user may have already
    # claimed ownership, and that is the intended end state.
    sudo chown "$USER:" "$color_json"
  fi
done <<<"$policy_dirs"
