echo "Add T2 Mac ACPI identity parameters"

if ! lspci -nn | grep "106b:180[12]" >/dev/null; then
  exit 0
fi

limine_conf="${OMARCHY_T2_LIMINE_CONF:-/etc/limine-entry-tool.d/t2-mac.conf}"
running_cmdline="${OMARCHY_T2_RUNNING_CMDLINE:-/proc/cmdline}"
repair_marker="${OMARCHY_T2_ACPI_REPAIR_MARKER:-/var/lib/omarchy/migrations/1787163407}"
required_params=(acpi_osi=!Darwin acpi_osi=Linux)
needs_limine_rebuild=0

[[ -f $limine_conf ]] || exit 0

limine_default_has_param() {
  local param="$1"
  grep -Eq "^[[:space:]]*KERNEL_CMDLINE\\[default\\]\\+=.*([[:space:]\"])${param}([[:space:]\"]|$)" "$limine_conf"
}

for param in "${required_params[@]}"; do
  if ! limine_default_has_param "$param"; then
    sudo sed -i "/^KERNEL_CMDLINE\[default\]+=/ s/\"[[:space:]]*$/ $param\"/" "$limine_conf"
    limine_default_has_param "$param" || {
      echo "Could not add $param to $limine_conf" >&2
      exit 1
    }
    needs_limine_rebuild=1
  fi
done

# The running kernel keeps its old command line until reboot. The machine-wide
# marker prevents another user's migration from repeating a successful rebuild,
# while a missing marker retries an interrupted rebuild.
if [[ ! -e $repair_marker ]]; then
  booted=""
  [[ -r $running_cmdline ]] && booted=$(<"$running_cmdline")

  for param in "${required_params[@]}"; do
    if [[ " $booted " != *" $param "* ]]; then
      needs_limine_rebuild=1
      break
    fi
  done
fi

if (( needs_limine_rebuild )); then
  sudo limine-mkinitcpio
  sudo install -Dm644 /dev/null "$repair_marker"
fi
