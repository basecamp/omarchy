echo "Close the world-writable browser policy directories"

# Browser enterprise policy directories are trust roots: browsers read every
# JSON file under policies/managed, and Firefox/Zen read distribution/
# policies.json, as administrator-managed policy. Omarchy used to make those
# directories world-writable so an unprivileged theme switch could drop
# color.json in, which let any local account install browser policy -- a forced
# extension, a proxy, a disabled protection -- without ever holding root.
# omarchy-theme-set-browser-policy now takes root for that one write, so put the
# directories back to 0755 root:root.

# Prefixed so the test can point the whole scan at a fixture. Empty in every
# real run.
prefix="${OMARCHY_BROWSER_POLICY_ROOT:-}"

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
# rename the real one aside and put their own in its place.
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

loose=()
for dir in "${policy_dirs[@]}" "${distribution_dirs[@]}" "${parent_dirs[@]}"; do
  [[ -d $dir ]] || continue

  mode=$(stat -c '%a' "$dir" 2>/dev/null) || continue
  # Group- or other-writable. Migrations run once per user, so on a machine
  # another user already repaired nothing reports loose and this no-ops.
  if ((8#$mode & 022)); then
    loose+=("$dir")
  fi
done

if ((${#loose[@]} == 0)); then
  exit 0
fi

if [[ -t 0 ]]; then
  elevate() { sudo "$@"; }
else
  elevate() { pkexec "$@"; }
fi

for dir in "${loose[@]}"; do
  echo "  Tightening $dir"
done

elevate chmod 0755 "${loose[@]}"

# color.json is Omarchy's own file and it sat in a directory anyone could write,
# so its contents are not trusted and it is not chowned into place. Remove it and
# let omarchy-theme-set-browser regenerate it through the privileged helper.
stale_color=()
for dir in "${policy_dirs[@]}"; do
  [[ -f $dir/color.json ]] && stale_color+=("$dir/color.json")
done

if ((${#stale_color[@]} > 0)); then
  elevate rm -f "${stale_color[@]}"
fi

# Same reasoning for policies.json, except Omarchy ships the authoritative copy,
# so restore it rather than dropping it. distribution.ini belongs to the browser
# package and is left alone.
for dir in "${distribution_dirs[@]}"; do
  [[ -f $dir/policies.json ]] || continue

  elevate install -m 0644 -o root -g root \
    "${OMARCHY_PATH:-/usr/share/omarchy}/default/firefox/policies.json" "$dir/policies.json"
done

# Anything else in a policy directory is either a policy the machine's admin put
# there deliberately or one planted while the directory was open to everyone.
# There is no way to tell them apart from here, so report them and change
# nothing: deleting a real admin policy would be its own bug.
unexpected=()
for dir in "${policy_dirs[@]}" "${distribution_dirs[@]}"; do
  [[ -d $dir ]] || continue

  for file in "$dir"/*; do
    [[ -f $file ]] || continue
    case "${file##*/}" in
    color.json | policies.json | distribution.ini) continue ;;
    esac
    unexpected+=("$file")
  done
done

if ((${#unexpected[@]} > 0)); then
  echo
  echo "  These files were in a browser policy directory while it was writable by any"
  echo "  local user. Omarchy did not put them there and has left them in place."
  echo "  Review them, and remove any you do not recognize:"
  for file in "${unexpected[@]}"; do
    echo "    $file"
  done
  echo
fi

# Repaint the browser accent through the privileged helper, so the color removed
# above comes back in this update rather than at the next theme switch.
omarchy-theme-set-browser || true
