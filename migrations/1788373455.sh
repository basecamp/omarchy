echo "Repair system-sleep hooks that were installed non-executable"

# cp -p from the Omarchy checkout copied these hooks with the repository's 644
# mode and the invoking user's ownership. systemd-sleep only runs executables,
# so the hooks were skipped silently on every suspend and resume.
for hook in force-igpu keyboard-backlight; do
  installed="/usr/lib/systemd/system-sleep/$hook"

  if [[ -f $installed && ! -x $installed ]]; then
    sudo install -D -o root -g root -m 755 \
      "$OMARCHY_PATH/default/systemd/system-sleep/$hook" "$installed"
  fi
done
