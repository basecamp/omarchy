echo "Stop world-writable Chromium and Firefox policy directories"

source "$OMARCHY_PATH/install/helpers/browser-policy.sh"

browser_policy_setup_group
browser_policy_grant_user "${USER:-$(id -un)}"

repaired=0
for dir in "${BROWSER_POLICY_MANAGED_DIRS[@]}"; do
  [[ -d $dir ]] || continue
  browser_policy_dir_hardened "$dir" && continue
  browser_policy_setup_dir "$dir"
  repaired=1
done

if (( repaired )); then
  omarchy-theme-set-browser
fi

for dir in "${BROWSER_POLICY_FIREFOX_DIRS[@]}"; do
  [[ -d $dir ]] || continue
  browser_policy_firefox_hardened "$dir" && continue
  browser_policy_setup_firefox_distribution "$dir"
done
