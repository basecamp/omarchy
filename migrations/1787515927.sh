echo "Stop world-writable Chromium and Firefox policy directories"

source "$OMARCHY_PATH/install/helpers/browser-policy.sh"

browser_policy_setup_group
browser_policy_grant_user "${USER:-$(id -un)}"

repaired=0
for dir in "${BROWSER_POLICY_MANAGED_DIRS[@]}"; do
  [[ -d $dir ]] || continue
  if browser_policy_dir_hardened "$dir" && browser_policy_parents_hardened "$dir"; then
    continue
  fi
  browser_policy_setup_dir "$dir"
  repaired=1
done

if (( repaired )); then
  omarchy-theme-set-browser
fi

for dir in "${BROWSER_POLICY_FIREFOX_DIRS[@]}"; do
  [[ -d $dir ]] || continue
  browser_policy_firefox_hardened "$dir" && continue
  as_root install -d -m 0755 -o root -g root "$dir"
  browser_policy_purge_dir "$dir"
  if ! browser_policy_firefox_policy_file_ok "$dir/policies.json"; then
    browser_policy_install_firefox_policies "$dir"
  fi
done
