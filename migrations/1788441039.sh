echo "Update Chromium browser policies to follow the system color scheme"

policy_files=(
  /etc/chromium/policies/managed/color.json
  /etc/opt/chrome/policies/managed/color.json
  /etc/opt/edge/policies/managed/color.json
  /etc/brave/policies/managed/color.json
)

for policy_file in "${policy_files[@]}"; do
  [[ -f $policy_file ]] || continue
  if grep -Fq '"BrowserColorScheme": "device"' "$policy_file"; then
    omarchy-theme-set-browser || true
    break
  fi
done
