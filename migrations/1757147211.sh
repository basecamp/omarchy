echo "Create managed policy directories for Chromium and Brave for theme switching"

for policy_dir in /etc/chromium/policies/managed /etc/brave/policies/managed; do
  sudo install -d -m 755 -o root -g root "$policy_dir"
  sudo rm -rf "$policy_dir/color.json"
  sudo install -m 664 -o root -g wheel /dev/null "$policy_dir/color.json"
done

omarchy-theme-set-browser
