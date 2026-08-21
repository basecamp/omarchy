echo "Make installed system-sleep hooks executable so systemd runs them"

sleep_hook_dir="${OMARCHY_SYSTEM_SLEEP_DIR:-/usr/lib/systemd/system-sleep}"

# omarchy-hibernation-setup and omarchy-toggle-hybrid-gpu copied these hooks
# into place with cp -p from a 644 source, and systemd-sleep(8) silently skips
# non-executable files here. Only the mode is wrong, so fix the mode in place:
# a hook that is absent or already executable is left alone, which also makes
# the second user's run on the same machine a no-op.
for hook in keyboard-backlight force-igpu; do
  path="$sleep_hook_dir/$hook"
  if [[ -f $path && ! -x $path ]]; then
    sudo chmod 755 "$path"
  fi
done
