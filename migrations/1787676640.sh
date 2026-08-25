echo "Secure browser managed-policy directories created by older Omarchy installs"

safe_admin_file() {
  local path=$1 mode

  [[ -f $path && ! -L $path ]] || return 1
  [[ $(stat -c '%u' -- "$path") == 0 ]] || return 1

  mode=$(stat -c '%a' -- "$path")
  (( (8#$mode & 022) == 0 ))
}

safe_admin_entry() {
  local path=$1 mode

  [[ ! -L $path && ( -f $path || -d $path ) ]] || return 1
  [[ $(stat -c '%u' -- "$path") == 0 ]] || return 1

  mode=$(stat -c '%a' -- "$path")
  (( (8#$mode & 022) == 0 ))
}

chromium_policy_dirs=(
  /etc/chromium/policies/managed
  /etc/opt/chrome/policies/managed
  /etc/opt/edge/policies/managed
  /etc/brave/policies/managed
)

chromium_needs_repair() {
  local policy_dir entry

  for policy_dir in "${chromium_policy_dirs[@]}"; do
    [[ -e $policy_dir || -L $policy_dir ]] || continue

    if [[ -L $policy_dir || ! -d $policy_dir || $(stat -c '%u:%g:%a' -- "$policy_dir") != "0:0:755" ]]; then
      return 0
    fi

    for entry in "$policy_dir"/*; do
      if [[ $entry == "$policy_dir/color.json" ]]; then
        [[ $(stat -c '%u:%g:%a' -- "$entry" 2>/dev/null || true) == "0:0:644" && ! -L $entry ]] || return 0
      elif ! safe_admin_file "$entry"; then
        return 0
      fi
    done
  done

  return 1
}

distribution_needs_repair() {
  local distribution_dir=$1 entry

  [[ -e $distribution_dir || -L $distribution_dir ]] || return 1
  if [[ -L $distribution_dir || ! -d $distribution_dir || $(stat -c '%u:%g:%a' -- "$distribution_dir") != "0:0:755" ]]; then
    return 0
  fi

  for entry in "$distribution_dir"/*; do
    safe_admin_entry "$entry" || return 0
  done

  return 1
}

repair_distribution() {
  local distribution_dir=$1 policy_file="$1/policies.json" entry

  if [[ -L $distribution_dir || ! -d $distribution_dir ]]; then
    echo "Refusing unsafe browser distribution path: $distribution_dir" >&2
    return 1
  fi

  sudo install -d -m 0755 -o root -g root "$distribution_dir"

  for entry in "$distribution_dir"/*; do
    if safe_admin_entry "$entry"; then
      continue
    fi

    printf 'Removing unsafe browser distribution entry: %q\n' "$entry" >&2
    sudo rm -rf -- "$entry"
  done

  # A root-owned directory squatting on the policy file name would survive the
  # cleanup above and then break the install below, so remove it like any other
  # anomaly at that exact name.
  if [[ -d $policy_file && ! -L $policy_file ]]; then
    printf 'Removing unsafe browser distribution entry: %q\n' "$policy_file" >&2
    sudo rm -rf -- "$policy_file"
  fi

  # Only install the packaged policy out of a root-owned Omarchy tree. A
  # dev-linked checkout must never choose what root writes into a machine-wide
  # policy path.
  if [[ $(stat -c '%u' -- "$OMARCHY_PATH") != 0 ]] ||
    [[ $(stat -c '%u' -- "$OMARCHY_PATH/default/firefox/policies.json") != 0 ]]; then
    echo "Keeping existing $policy_file: $OMARCHY_PATH is not a root-owned Omarchy tree" >&2
    return 0
  fi

  if ! safe_admin_file "$policy_file"; then
    sudo install -m 0644 -o root -g root -T "$OMARCHY_PATH/default/firefox/policies.json" "$policy_file"
  fi
}

(
  shopt -s dotglob nullglob

  # One refused path (an admin-symlinked policy directory, say) must not stop
  # the remaining repairs or leave this migration permanently pending.
  if chromium_needs_repair; then
    omarchy-theme-set-browser ||
      echo "Browser policy repair could not finish the Chromium theme write" >&2
  fi

  for distribution_dir in /usr/lib/firefox/distribution /opt/zen-browser/distribution; do
    if distribution_needs_repair "$distribution_dir"; then
      repair_distribution "$distribution_dir" ||
        echo "Browser policy repair could not secure $distribution_dir" >&2
    fi
  done
)
