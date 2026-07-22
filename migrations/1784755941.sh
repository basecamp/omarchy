echo "Enable Dell firmware power profiles without a reboot"

for profile_dir in /sys/class/platform-profile/*; do
  [[ -r $profile_dir/name && -r $profile_dir/profile ]] || continue
  [[ $(<"$profile_dir/name") == "dell-pc" ]] || continue
  if [[ ! -w $profile_dir/profile ]]; then
    pkexec /bin/bash -c \
      '/usr/bin/udevadm control --reload && /usr/bin/udevadm trigger --settle --action=add --subsystem-match=platform-profile'
    [[ -w $profile_dir/profile ]] || { echo "Dell power profile is still not writable" >&2; exit 1; }
  fi
  break
done
