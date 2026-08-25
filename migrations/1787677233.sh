echo "Close the world-writable browser policy directories"

# Browser enterprise policy directories are trust roots: browsers read every
# JSON file under policies/managed, and Firefox/Zen read distribution/
# policies.json, as administrator-managed policy. Omarchy used to make those
# directories world-writable so an unprivileged theme switch could drop
# color.json in, which let any local account install browser policy -- a forced
# extension, a proxy, a disabled protection -- without ever holding root.
# omarchy-theme-set-browser-policy now takes root for that one write, so put the
# directories back to 0755 root:root.
#
# Restoring the mode is not enough on its own. While a directory was writable,
# an ordinary account could move the real one aside and leave its own in place,
# or leave behind a policy file it still owns. Either survives a chmod: the
# directory reports a tight mode while its owner can still reopen it, and the
# file stays writable by the account that planted it. So this checks ownership
# as well as mode, and moves anything an ordinary account still controls out of
# the trust root rather than leaving it live.

# Prefixed so the test can point the whole scan at a fixture. Empty in every
# real run.
prefix="${OMARCHY_BROWSER_POLICY_ROOT:-}"

# Root-only, and outside the browser policy tree: a copy left beside the
# original would still be read as policy. Mirrors the full path the way
# omarchy-update-system-pkgs-when-conflicted does.
quarantine="${OMARCHY_BROWSER_POLICY_QUARANTINE:-$prefix/var/lib/omarchy/quarantine/browser-policy}"

# uid 0 everywhere but the test, which cannot create root-owned fixtures.
expected_owner="${OMARCHY_BROWSER_POLICY_OWNER:-0}"

policy_dirs=(
  "$prefix/etc/chromium/policies/managed"
  "$prefix/etc/opt/chrome/policies/managed"
  "$prefix/etc/opt/edge/policies/managed"
  "$prefix/etc/brave/policies/managed"
)

distribution_dirs=(
  "$prefix/usr/lib/firefox/distribution"
  "$prefix/opt/zen-browser/distribution"
)

# The quattro transition created the chromium directory with mode 0777, and that
# mode lands on every directory the command had to create, so a machine with no
# /etc/chromium before the upgrade got a world-writable parent chain too. A
# writable parent is as good as a writable policy directory: it lets any user
# rename the real one aside and put their own in its place. Shallowest first, so
# a compromised parent is dealt with before the children it carries.
parent_dirs=(
  "$prefix/etc/chromium"
  "$prefix/etc/chromium/policies"
  "$prefix/etc/opt/chrome"
  "$prefix/etc/opt/chrome/policies"
  "$prefix/etc/opt/edge"
  "$prefix/etc/opt/edge/policies"
  "$prefix/etc/brave"
  "$prefix/etc/brave/policies"
)

# Paths carry no "|", so a joined string is set enough for this.
present_marker=""
repair_marker=""

present() { [[ $present_marker == *"|$1|"* ]]; }
needs_repair() { [[ $repair_marker == *"|$1|"* ]]; }

for dir in "${parent_dirs[@]}" "${policy_dirs[@]}" "${distribution_dirs[@]}"; do
  # -L first, because the checks below cannot speak for a symlink. [[ -d ]] and
  # chmod follow one; stat does not, so it would report the link's own 0777
  # rather than anything about the directory finally written to. A link whose
  # target does not exist yet fails [[ -d ]] outright and would be skipped
  # entirely, leaving the path for its owner to fill in later.
  if [[ -L $dir ]]; then
    present_marker+="|$dir|"
    repair_marker+="|$dir|"
    continue
  fi

  [[ -d $dir ]] || continue
  present_marker+="|$dir|"

  owner=$(stat -c '%u' "$dir" 2>/dev/null) || continue
  mode=$(stat -c '%a' "$dir" 2>/dev/null) || continue

  # Not root's, or group- or other-writable.
  if [[ $owner != "$expected_owner" ]] || ((8#$mode & 022)); then
    repair_marker+="|$dir|"
  fi
done

# Migrations run once per user, so on a machine another user already repaired
# nothing needs repair and this no-ops.
if [[ -z $repair_marker ]]; then
  exit 0
fi

if [[ -t 0 ]]; then
  elevate() { sudo "$@"; }
else
  elevate() { pkexec "$@"; }
fi

unexpected=()

quarantine_path() {
  local path="$1"
  local reason="$2"
  local target="$quarantine$path"
  local n=1

  while [[ -e $target || -L $target ]]; do
    target="$quarantine$path.$n"
    n=$((n + 1))
  done

  elevate install -d -m 0700 -o root -g root "${target%/*}"
  elevate mv -T "$path" "$target"
  echo "  Quarantined $path"
  echo "    $reason"
  echo "    Moved to $target"
}

# Leaves the path a real, root-owned, 0755 directory, whatever was there before.
ensure_root_dir() {
  local dir="$1"
  local owner

  if [[ -L $dir ]]; then
    quarantine_path "$dir" "the policy directory had been replaced by a symlink"
  elif [[ -d $dir ]]; then
    owner=$(stat -c '%u' "$dir")
    if [[ $owner != "$expected_owner" ]]; then
      quarantine_path "$dir" "the policy directory was owned by uid $owner, not root"
    fi
  fi

  # install -d applies the mode only to the last component, which is why every
  # parent is on the list above. It also recreates a directory whose compromised
  # parent was just quarantined out from under it.
  elevate install -d -m 0755 -o root -g root "$dir"
}

# Parents before the directories they carry.
for dir in "${parent_dirs[@]}" "${policy_dirs[@]}" "${distribution_dirs[@]}"; do
  present "$dir" || continue
  ensure_root_dir "$dir"
done

for dir in "${policy_dirs[@]}" "${distribution_dirs[@]}"; do
  [[ -d $dir ]] || continue

  for file in "$dir"/*; do
    [[ -f $file || -L $file ]] || continue

    name=${file##*/}

    # A symlink in a policy directory is never Omarchy's, and the install below
    # would write straight through it as root.
    if [[ -L $file ]]; then
      quarantine_path "$file" "a policy file had been replaced by a symlink"
      continue
    fi

    # Omarchy's own files. Both sat where anyone could write, so neither is
    # trusted: color.json is regenerated by the repaint below, and policies.json
    # is reinstalled from the shipped copy.
    if [[ $name == "color.json" && $dir != *"/distribution" ]]; then
      elevate rm -f "$file"
      continue
    fi
    if [[ $name == "policies.json" && $dir == *"/distribution" ]]; then
      elevate rm -f "$file"
      continue
    fi

    owner=$(stat -c '%u' "$file")
    mode=$(stat -c '%a' "$file")

    # A file an ordinary account owns, or can still write, stays under that
    # account's control after this migration. Reporting it would leave it live,
    # so move it out of the trust root instead.
    if [[ $owner != "$expected_owner" ]] || ((8#$mode & 022)); then
      quarantine_path "$file" "an ordinary account could still change this policy file"
      continue
    fi

    # Root's, and no ordinary account can write it. distribution.ini is the
    # browser package's own file; anything else is most likely a policy this
    # machine's administrator put there deliberately, and deleting that would be
    # its own bug. Neither is under an attacker's control, so both stay.
    if [[ $name != "distribution.ini" ]]; then
      unexpected+=("$file")
    fi
  done
done

# Omarchy ships the authoritative Firefox/Zen policy. Restore it wherever this
# migration had to repair the directory: an account that could write the
# directory could equally have deleted the file, so keying on the file still
# being there would leave the policy missing.
for dir in "${distribution_dirs[@]}"; do
  present "$dir" || continue
  needs_repair "$dir" || [[ -f $dir/policies.json ]] || continue

  elevate install -m 0644 -o root -g root \
    "${OMARCHY_PATH:-/usr/share/omarchy}/default/firefox/policies.json" "$dir/policies.json"
done

if ((${#unexpected[@]} > 0)); then
  echo
  echo "  These files were in a browser policy directory while it was writable by any"
  echo "  local user. They belong to root and no ordinary account can change them now,"
  echo "  so Omarchy has left them in place. Review them, and remove any you do not"
  echo "  recognize:"
  for file in "${unexpected[@]}"; do
    echo "    $file"
  done
  echo
fi

# Repaint the browser accent through the privileged helper, so the color removed
# above comes back in this update rather than at the next theme switch.
omarchy-theme-set-browser || true
