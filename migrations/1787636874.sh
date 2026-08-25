echo "Lock down world-writable browser managed-policy directories"

# Omarchy used to make each browser's managed-policy directory world-writable
# (chmod a+rw) so the theme colour file could be written as the user. A
# world-writable managed-policy directory lets any local user or process drop a
# mandatory browser policy -- an extension forcelist, a proxy, disabled Safe
# Browsing -- that every browser then obeys. Close that on existing installs.
#
# Locking the directory is not enough on its own: a policy file another account
# already dropped, or one left group/other-writable, stays under that account's
# control afterwards. So each entry is repaired too. A managed-policy directory
# holds only regular policy files; a symlink there is never legitimate, and a
# file owned by neither root nor the theming user was planted by another account
# while the directory was open, so neither survives the repair.
#
# Chromium-family directories are still written by the user who themes the
# browser (color.json), so they are handed to this user at 0755 and that user may
# keep a writable color.json. Firefox/zen only ever receive a root-written
# policies.json, so they return to root ownership and keep no user-writable file.

lock_policy_dir() {
  local dir="$1"
  local owner="$2"
  local keep_owner="$3" # account allowed to keep a writable file, or empty for root-only dirs

  [[ -d $dir ]] || return 0

  # Only act while something is still wrong: the directory is group/other-writable,
  # or it holds a symlink or a group/other-writable entry. After the repair, and
  # for a second user on the machine, this is a no-op and needs no privilege prompt.
  if [[ -z $(find "$dir" -maxdepth 0 -perm /022 -print 2>/dev/null) &&
        -z $(find "$dir" -mindepth 1 -maxdepth 1 \( -type l -o -perm /022 \) -print 2>/dev/null) ]]; then
    return 0
  fi

  local entry entry_owner
  while IFS= read -r -d '' entry; do
    if [[ -L $entry ]]; then
      sudo rm -f "$entry"
      continue
    fi
    entry_owner=$(stat -c '%U' "$entry" 2>/dev/null || echo "")
    if [[ $entry_owner != "root" && ( -z $keep_owner || $entry_owner != "$keep_owner" ) ]]; then
      sudo rm -f "$entry"
      continue
    fi
    sudo chmod go-w "$entry"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

  sudo chown "$owner" "$dir"
  sudo chmod 755 "$dir"
}

for dir in \
  /etc/chromium/policies/managed \
  /etc/opt/chrome/policies/managed \
  /etc/opt/edge/policies/managed \
  /etc/brave/policies/managed; do
  lock_policy_dir "$dir" "$USER:$(id -gn)" "$USER"
done

for dir in \
  /usr/lib/firefox/distribution \
  /opt/zen-browser/distribution; do
  lock_policy_dir "$dir" "root:root" ""
done
