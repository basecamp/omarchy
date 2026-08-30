echo "Stop T2 Mac resume from waiting on the Thunderbolt controllers"

if ! lspci -nn | grep "106b:180[12]" >/dev/null; then
  exit 0
fi

hook="${OMARCHY_T2_THUNDERBOLT_HOOK:-/usr/lib/systemd/system-sleep/omarchy-t2-thunderbolt}"

if [[ -x $hook ]]; then
  exit 0
fi

# The Thunderbolt controllers lose power in deep sleep and the kernel then
# spends ~18 s of every resume waiting on them, one after another. The sleep
# hook takes them out before suspend and re-enumerates them after.
sudo install -Dm755 "$OMARCHY_PATH/default/systemd/system-sleep/t2-thunderbolt" "$hook"
