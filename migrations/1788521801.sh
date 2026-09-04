echo "Remove the unused fred=on kernel command line"

# Linux 7.1 enables FRED by default and only reads fred=off. The drop-in
# install/hardware/intel/fred.sh wrote is ignored and logged as an unknown
# parameter. Delete the exact file Omarchy shipped; leave an edited copy alone.

drop_in=/etc/limine-entry-tool.d/intel-panther-lake-fred.conf
rebuild_needed=/var/lib/omarchy/migrations/1788521801-rebuild-needed
limine_mkinitcpio=/usr/bin/limine-mkinitcpio
install_command=/usr/bin/install
rm_command=/usr/bin/rm

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

finish_pending_rebuild() {
  if [[ -x $limine_mkinitcpio ]]; then
    if ! as_root "$limine_mkinitcpio"; then
      echo "Could not rebuild the boot image after removing fred=on. Ask an administrator to run omarchy-migrate." >&2
      exit 1
    fi
  fi

  if ! as_root "$rm_command" -f -- "$rebuild_needed"; then
    echo "Could not finish the fred=on drop-in repair. Ask an administrator to run omarchy-migrate." >&2
    exit 1
  fi
}

if [[ -e $rebuild_needed && ! -e $drop_in ]]; then
  finish_pending_rebuild
fi

[[ -f $drop_in ]] || exit 0

expected=$(mktemp)
trap 'rm -f "$expected"' EXIT
printf '%s\n' '# Intel Panther Lake FRED support' 'KERNEL_CMDLINE[default]+=" fred=on"' >"$expected"
cmp -s "$drop_in" "$expected" || exit 0
rm -f "$expected"
trap - EXIT

if ! as_root "$install_command" -Dm644 /dev/null "$rebuild_needed"; then
  echo "Administrator privileges are required to remove the unused fred=on kernel command line. Ask an administrator to run omarchy-migrate." >&2
  exit 1
fi

if ! as_root "$rm_command" -f -- "$drop_in"; then
  echo "Administrator privileges are required to remove the unused fred=on kernel command line. Ask an administrator to run omarchy-migrate." >&2
  exit 1
fi

finish_pending_rebuild
