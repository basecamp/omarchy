echo "Install omarchy-battery-policy package"

if ! pacman -Q omarchy-battery-policy >/dev/null 2>&1; then
  omarchy-pkg-add omarchy-battery-policy
fi
