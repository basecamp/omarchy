echo "Make installed system-sleep hooks executable so systemd runs them"

sleep_hook_dir="${OMARCHY_SYSTEM_SLEEP_DIR:-/usr/lib/systemd/system-sleep}"

# force-igpu switches the GPU back to Integrated after every sleep, so it may
# only be live on a machine that is still in Integrated mode. The toggle removes
# the hook when it switches to Hybrid, but a mode change made directly through
# supergfxctl leaves the copy behind, and that copy has been inert and must
# stay that way. Ask supergfxd the way the toggle does; no answer means the
# hook is left as it is.
integrated_gpu_mode() {
  local attempt mode

  for attempt in {1..3}; do
    if mode=$(timeout --kill-after=1s 3s supergfxctl -g 2>/dev/null) && [[ -n $mode ]]; then
      [[ $mode == "Integrated" ]]
      return
    fi

    (( attempt < 3 )) && sleep 1
  done

  return 1
}

# omarchy-hibernation-setup and omarchy-toggle-hybrid-gpu copied these hooks
# into place with cp -p from a 644 source, and systemd-sleep(8) silently skips
# non-executable files here. Only the mode is wrong, so fix the mode in place:
# a hook that is absent or already executable is left alone, which also makes
# the second user's run on the same machine a no-op.
for hook in keyboard-backlight force-igpu; do
  path="$sleep_hook_dir/$hook"

  if [[ ! -f $path || -x $path ]]; then
    continue
  fi

  if [[ $hook == "force-igpu" ]] && ! integrated_gpu_mode; then
    continue
  fi

  sudo chmod 755 "$path"
done
