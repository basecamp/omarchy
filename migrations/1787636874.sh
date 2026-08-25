echo "Lock down world-writable browser managed-policy directories"

# Omarchy used to make each browser's managed-policy directory world-writable
# (chmod a+rw) so the theme colour file could be written as the user. A
# world-writable managed-policy directory lets any local user or process drop a
# mandatory browser policy -- an extension forcelist, a proxy, disabled Safe
# Browsing -- that every browser then obeys. Close that on existing installs.
# Chromium-family directories are still written by the user who themes the
# browser, so they are handed to this user at 0755; firefox/zen only ever receive
# a root-written policies.json, so they return to root ownership.

lock_policy_dir() {
  local dir="$1"
  local owner="$2"

  [[ -d $dir ]] || return 0

  # Only act while the directory is still group- or other-writable. A second user
  # on the machine, or a re-run after the repair, then needs no privilege prompt
  # and changes nothing.
  if [[ -z $(find "$dir" -maxdepth 0 -perm /022 -print 2>/dev/null) ]]; then
    return 0
  fi

  sudo chown "$owner" "$dir"
  sudo chmod 755 "$dir"
}

for dir in \
  /etc/chromium/policies/managed \
  /etc/opt/chrome/policies/managed \
  /etc/opt/edge/policies/managed \
  /etc/brave/policies/managed; do
  lock_policy_dir "$dir" "$USER:$(id -gn)"
done

for dir in \
  /usr/lib/firefox/distribution \
  /opt/zen-browser/distribution; do
  lock_policy_dir "$dir" "root:root"
done
