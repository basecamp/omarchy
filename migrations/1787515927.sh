echo "Stop world-writable Chromium and Firefox policy directories"

source "$OMARCHY_PATH/install/helpers/browser-policy.sh"

repaired=0
for dir in "${BROWSER_POLICY_MANAGED_DIRS[@]}"; do
  [[ -d $dir || -L $dir ]] || continue
  browser_policy_setup_dir "$dir"
  repaired=1
done

# Repainting the policy color is cosmetic and the next theme change redoes it.
# Under bash -euo pipefail a failure here would abort the migration before the
# Firefox directories below are hardened, and the marker would never be written.
if (( repaired )); then
  omarchy-theme-set-browser || true
fi

for dir in "${BROWSER_POLICY_FIREFOX_DIRS[@]}"; do
  [[ -d $dir || -L $dir ]] || continue
  if browser_policy_firefox_hardened "$dir"; then
    browser_policy_purge_dir "$dir"
    continue
  fi
  browser_policy_setup_parent "$dir"
  browser_policy_purge_dir "$dir"
  if ! browser_policy_firefox_policy_file_ok "$dir/policies.json"; then
    browser_policy_install_firefox_policies "$dir"
  fi
done
