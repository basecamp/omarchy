# Dell Latitude 7490 systems with the Kaby Lake-R iGPU can hang while resuming
# from hibernation in intel_power_domains_resume(). Disabling display C-states
# avoids the broken DPLL/CDCLK restore path while leaving PSR and FBC enabled.

dmi_vendor_file="${OMARCHY_LATITUDE_7490_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}"
dmi_product_file="${OMARCHY_LATITUDE_7490_DMI_PRODUCT:-/sys/class/dmi/id/product_name}"
limine_conf="${OMARCHY_LATITUDE_7490_LIMINE_CONF:-/etc/limine-entry-tool.d/dell-latitude-7490-i915.conf}"
repair_marker="${OMARCHY_LATITUDE_7490_REPAIR_MARKER:-/var/lib/omarchy/migrations/1787689809}"
OMARCHY_LATITUDE_7490_CHANGED=0

dmi_vendor=""
dmi_product=""
[[ -r $dmi_vendor_file ]] && read -r dmi_vendor <"$dmi_vendor_file"
[[ -r $dmi_product_file ]] && read -r dmi_product <"$dmi_product_file"

if [[ $dmi_vendor == "Dell Inc." && $dmi_product == "Latitude 7490" ]]; then
  expected='KERNEL_CMDLINE[default]+=" i915.enable_dc=0"'

  if [[ ! -f $limine_conf ]] || [[ $(<"$limine_conf") != "$expected" ]]; then
    sudo rm -f "$repair_marker"
    printf '%s\n' "$expected" | sudo install -Dm644 /dev/stdin "$limine_conf"
  fi

  if [[ ! -e $repair_marker ]]; then
    sudo limine-mkinitcpio
    sudo install -Dm644 /dev/null "$repair_marker"
    OMARCHY_LATITUDE_7490_CHANGED=1
  fi
fi
