#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

lab_vm="$ROOT/bin/omarchy-lab-vm"
lab_viewer="$ROOT/bin/omarchy-lab-viewer"
lab_rules="$ROOT/default/hypr/apps/lab-vm.lua"
menu="$ROOT/default/omarchy/omarchy-menu.jsonc"

[[ -x $lab_vm ]] || fail "omarchy-lab-vm is executable"
pass "omarchy-lab-vm is executable"

[[ -x $lab_viewer ]] || fail "omarchy-lab-viewer is executable"
rg -q '^# omarchy:summary=' "$lab_viewer" || fail "omarchy-lab-viewer declares a summary"
pass "omarchy-lab-viewer is executable and declares command metadata"

rg -q '^# omarchy:summary=' "$lab_vm" || fail "omarchy-lab-vm declares a summary"
rg -q 'omarchy:requires-sudo=true' "$lab_vm" || fail "omarchy-lab-vm is marked as requiring sudo"
pass "omarchy-lab-vm declares command metadata"

rg -q 'StrictHostKeyChecking=no' "$lab_vm" ||
  fail "lab SSH must ignore rotating guest host keys"
rg -q 'UserKnownHostsFile=/dev/null' "$lab_vm" ||
  fail "lab SSH must not persist rotating guest host keys"
rg -q 'LogLevel=QUIET' "$lab_vm" ||
  fail "lab SSH must not print the host-key MITM banner"
rg -q 'ssh-keygen -q' "$lab_vm" ||
  fail "lab SSH keygen must be quiet"
rg -q 'Guest is off; starting' "$lab_vm" ||
  fail "wait_ssh restarts a guest that powered off after install"
rg -q 'omarchy-lab-viewer.*run' "$lab_vm" ||
  fail "Lab VM launch paths use the dedicated viewer controller"
rg -q -- '--attach' "$lab_viewer" && rg -q -- '--reconnect' "$lab_viewer" ||
  fail "virt-viewer reconnects after the guest installer reboots"
rg -q 'systemd-run --user' "$lab_vm" ||
  fail "virt-viewer must be a user unit so the installer terminal can close"
if awk '/^ensure_viewer\(\)/,/^}/' "$lab_vm" | rg -q 'uwsm-app --'; then
  fail "ensure_viewer must not wrap uwsm-app; it exits and systemd-run would respawn"
fi
if awk '/^wait_ssh\(\)/,/^}/' "$lab_vm" | rg -q ensure_viewer; then
  fail "wait_ssh must not spawn virt-viewer every poll"
fi
pass "wait_ssh does not flood virt-viewer"
rg -q 'remove_ssh_artifacts' "$lab_vm" ||
  fail "remove deletes the lab SSH key and host entries"
pass "wait_ssh survives ISO reboot and host-key rotation"
if rg -q 'systemctl reboot' "$lab_vm"; then
  fail "install must not reboot after configure_guest; overlay boot is the new-UKI boot"
fi
pass "install freezes gold without a UKI-rebuild reboot"

resize_helper="$ROOT/default/lab-vm/display-resize"
[[ -f $resize_helper ]] || fail "lab VM ships a guest SPICE display-resize helper"
rg -q 'udevadm monitor --udev --subsystem-match=drm' "$resize_helper" ||
  fail "display-resize watches DRM hotplugs from virt-viewer auto-resize"
rg -q 'hl.monitor' "$resize_helper" ||
  fail "display-resize applies the virtio-gpu mode through Hyprland Lua"
rg -q 'force_renderer_reload' "$resize_helper" ||
  fail "display-resize reattaches the SPICE scanout after a Hyprland reload"
rg -q 'wtype -M shift' "$resize_helper" ||
  fail "display-resize wakes DPMS after a modeset without typing into the guest"
rg -q 'Virtual-\*' "$resize_helper" ||
  fail "display-resize only touches QEMU Virtual-* outputs"
if rg -q '1920x1080|5120x1440|1280x800' "$resize_helper" "$ROOT/default/lab-vm/display-resize.service"; then
  fail "display-resize must not hard-code a host resolution"
fi
rg -q 'HYPERVISOR_PACKAGES=\(spice-vdagent\)' "$lab_vm" ||
  fail "configure_guest installs spice-vdagent so the client can publish framebuffer size"
if rg -q 'LAB_VM_ROOT\|readlink -f.*BASH_SOURCE' "$lab_vm"; then
  fail "lab VM defaults must resolve through OMARCHY_PATH"
fi
rg -q -- '--auto-resize=' "$lab_viewer" ||
  fail "virt-viewer requests guest auto-resize"
rg -q 'install_guest_display_resize' "$lab_vm" ||
  fail "configure_guest installs the display-resize user unit"
rg -q 'systemctl --user restart omarchy-lab-display-resize.service' "$lab_vm" ||
  fail "reinstalling the helper restarts an already-running resize service"
rg -q -- '--setenv=OMARCHY_PATH=' "$lab_vm" ||
  fail "Lab viewer services preserve the selected Omarchy tree"
pass "lab VM follows virt-viewer size instead of a fixed guest mode"

rg -q 'echo "Reusing \$iso_path" >&2' "$lab_vm" ||
  fail "ISO reuse status must not pollute command substitution"
if rg -n 'echo "Reusing \$iso_path"$' "$lab_vm" | rg -v '>&2'; then
  fail "ISO reuse status leaked to stdout"
fi
pass "ISO reuse status goes to stderr"

rg -q '/usr/bin/python3 /usr/bin/virt-install' "$lab_vm" ||
  fail "lab VM calls virt-install with the system Python"
if rg -q -- '--boot.*secboot' "$lab_vm"; then
  fail "lab VM does not use the Secure Boot OVMF firmware"
fi
rg -q 'OVMF_CODE.4m.fd' "$lab_vm" || fail "lab VM boots OVMF_CODE.4m.fd"
rg -q 'model=tpm-crb' "$lab_vm" || fail "lab VM attaches a software TPM"
pass "lab VM uses system virt-install, OVMF, and a software TPM"

if rg -q 'setfacl' "$lab_vm"; then
  fail "lab VM must not ACL the home directory for libvirt-qemu"
fi
rg -q '/var/lib/libvirt/images' "$lab_vm" ||
  fail "lab VM keeps disks and the ISO in the libvirt image pool"
pass "lab VM does not punch a search ACL through HOME"

rg -q "to any port 67" "$lab_vm" || fail "lab VM allows DHCP broadcasts to 255.255.255.255:67"
if rg -q "ufw allow in on virbr0'" "$lab_vm" || rg -q 'ufw allow in on virbr0"' "$lab_vm"; then
  fail "lab VM must not allow every port on virbr0"
fi
rg -q 'ufw route allow in on virbr0 out on' "$lab_vm" ||
  fail "lab VM forwards NAT only toward the uplink"
pass "lab VM installs tight UFW rules for libvirt NAT"

rg -q 'o.window\("virt-viewer"' "$lab_rules" ||
  fail "lab VM opacity rule targets virt-viewer"
rg -q 'tag = "-default-opacity"' "$lab_rules" || fail "lab VM opts out of default opacity"
rg -q 'opacity = "1 1"' "$lab_rules" || fail "lab VM stays fully opaque"
pass "lab VM stays fully opaque"

rg -q '"install.lab"' "$menu" || fail "menu offers Install > Lab"
rg -q '"remove.lab"' "$menu" || fail "menu offers Remove > Lab"
rg -q '"trigger.lab-controls"' "$menu" || fail "menu offers Trigger > Lab Controls"
rg -q '"when":"omarchy-lab-viewer active"' "$menu" || fail "Lab Controls only appears while the viewer is open"
rg -q 'shell summon omarchy.lab' "$menu" || fail "Lab Controls summons the native plugin"
if rg -q '"setup.lab-aspect-ratio"' "$menu"; then
  fail "Lab aspect ratio no longer occupies the global Setup menu"
fi
rg -q 'omarchy-bar put omarchy.lab' "$lab_vm" || fail "install puts the Lab widget on the bar"
rg -q 'setPluginEnabled omarchy.lab false' "$lab_vm" || fail "remove disables the Lab plugin"
rg -q 'Exec=omarchy-lab-viewer launch' "$lab_vm" || fail "desktop launch uses the viewer controller without nesting app scopes"
rg -q 'Categories=System;Emulator;' "$lab_vm" || fail "desktop launch uses registered application categories"
awk '/^screenshot_lab\(\)/,/^}/' "$lab_vm" | rg -q 'run_virsh screenshot .* >/dev/null' ||
  fail "screenshot prints only its reusable output path"
pass "menu, bar, and desktop launcher wire the native Lab controls"

tmpdir=$(mktemp -d)
export HOME="$tmpdir/home"
mkdir -p "$HOME"
trap 'rm -rf "$tmpdir"' EXIT

(
  # shellcheck disable=SC1090
  source "$lab_vm"
  run_virsh() {
    printf '%s\n' "$NAME"
    seq 1 100000
  }
  have_domain && domain_running
) || fail "domain probes consume all virsh output without a pipefail race"
pass "domain probes do not race virsh output"

# shellcheck disable=SC1090
source "$lab_vm"

[[ $(lab_resource_plan 123 32) == "4 8 8 16 16 32 24 92" ]] ||
  fail "large hosts keep workload-based profiles and custom headroom"
[[ $(lab_resource_plan 31 16) == "4 8 8 16 12 20 12 20" ]] ||
  fail "ordinary hosts cap high profiles to retained host capacity"
[[ $(lab_resource_plan 7 4) == "3 4 3 4 3 4 3 4" ]] ||
  fail "small hosts keep a viable bounded Lab allocation"
if rg -q '^RAM_DEFAULT=\|^CORES_DEFAULT=' "$lab_vm"; then
  fail "Lab installer defaults must derive from host hardware"
fi
rg -q 'safe limit:' "$lab_vm" || fail "Lab installer explains its host-safe limits"
pass "Lab installer derives resource recommendations from host hardware"

for ratio in 16:9 16:10 3:2 4:3 21:9 32:9; do
  valid_aspect_ratio "$ratio" || fail "common aspect ratio is accepted" "$ratio"
done
if valid_aspect_ratio 5:4; then
  fail "unsupported aspect ratios are rejected"
fi
omarchy-menu-select() { printf '16:10\tProductivity\n'; }
[[ $(pick_aspect_ratio) == "16:10" ]] || fail "aspect picker returns the selected ratio without its description"
unset -f omarchy-menu-select

read -r guest_width guest_height outer_width outer_height < <(
  aspect_window_size 16:9 2460 883 0 47 5040 1334
)
[[ $guest_width == 2288 && $guest_height == 1287 && $outer_width == 2288 && $outer_height == 1334 ]] ||
  fail "16:9 is exact and fits beneath host chrome" "$guest_width $guest_height $outer_width $outer_height"

read -r guest_width guest_height outer_width outer_height < <(
  aspect_window_size 21:9 1920 1080 0 47 5000 2000
)
[[ $guest_width == 4557 && $guest_height == 1953 && $outer_width == 4557 && $outer_height == 2000 ]] ||
  fail "aspect resizing maximizes the viewer within the host monitor" "$guest_width $guest_height $outer_width $outer_height"

read -r guest_width guest_height outer_width outer_height < <(
  aspect_window_size 16:10 1009 1074 0 48 3840 1334 125
)
[[ $guest_width == 1632 && $guest_height == 1020 && $outer_width == 2040 && $outer_height == 1323 ]] ||
  fail "aspect sizing accounts for viewer zoom" "$guest_width $guest_height $outer_width $outer_height"
pass "common aspect ratios preserve exact guest dimensions and maximize the host monitor"

aspect_calls="$tmpdir/aspect-calls"
have_domain() { return 0; }
domain_running() { return 0; }
ensure_viewer() { :; }
wait_ssh() { :; }
ensure_guest_display_resize() { :; }
wait_viewer_geometry() { printf '%s\n' '0xabc 2460 930 1 false 2460 883 0 47'; }
viewer_monitor_available_geometry() { printf '%s\n' '40 66 5040 1334'; }
wait_guest_display_update() { printf '%s\n' '2288 1287'; }
hypr_dispatch() { printf '%s\n' "$*" >>"$aspect_calls"; }

resize_viewer_aspect 16:9 >/dev/null
rg -q 'float.*address:0xabc' "$aspect_calls" || fail "aspect control floats a tiled viewer"
rg -q 'move.*x = 40, y = 66' "$aspect_calls" || fail "aspect control makes room before enlarging the viewer"
rg -q 'resize.*x = 2288, y = 1334' "$aspect_calls" || fail "aspect control resizes the viewer around exact guest dimensions"
rg -q 'center.*address:0xabc' "$aspect_calls" || fail "aspect control centers the resized viewer"
pass "aspect control floats, resizes, and centers the live viewer"

resize_home="$tmpdir/resize-home"
resize_drm="$tmpdir/drm"
resize_bin="$tmpdir/resize-bin"
resize_calls="$tmpdir/resize-calls"
resize_monitors="$resize_home/.config/hypr/monitors.lua"
mkdir -p "$resize_home/.config/hypr" "$resize_drm/card1-Virtual-1" "$resize_bin"
printf '%s\n' 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })' >"$resize_monitors"
printf '%s\n' connected >"$resize_drm/card1-Virtual-1/status"
printf '%s\n' 1440x900 >"$resize_drm/card1-Virtual-1/modes"

cat >"$resize_bin/hyprctl" <<'SH'
#!/bin/bash
if [[ $1 == "monitors" && ${2:-} == "-j" ]]; then
  printf '%s\n' '[{"name":"Virtual-1","width":1280,"height":800}]'
else
  printf '%s\n' "$*" >>"$RESIZE_CALLS"
fi
SH
cat >"$resize_bin/wtype" <<'SH'
#!/bin/bash
printf 'wtype %s\n' "$*" >>"$RESIZE_CALLS"
SH
chmod +x "$resize_bin/hyprctl" "$resize_bin/wtype"

PATH="$resize_bin:$PATH" \
  HOME="$resize_home" \
  HYPRLAND_INSTANCE_SIGNATURE=test \
  OMARCHY_LAB_DRM_ROOT="$resize_drm" \
  OMARCHY_LAB_MONITORS_LUA="$resize_monitors" \
  RESIZE_CALLS="$resize_calls" \
  "$resize_helper" --once

rg -q 'output = "Virtual-1", mode = "1440x900"' "$resize_monitors" ||
  fail "display-resize writes the virtio-gpu mode to monitors.lua"
[[ $(rg -c '^-- BEGIN OMARCHY-LAB-SPICE$' "$resize_monitors") == 1 ]] ||
  fail "display-resize writes one managed monitor block"
rg -qx reload "$resize_calls" || fail "display-resize reloads Hyprland"
rg -q 'force_renderer_reload' "$resize_calls" || fail "display-resize refreshes the SPICE scanout"
rg -q 'wtype -M shift -m shift' "$resize_calls" || fail "display-resize wakes the guest display"

printf '%s\n' 1600x950 >"$resize_drm/card1-Virtual-1/modes"
PATH="$resize_bin:$PATH" \
  HOME="$resize_home" \
  HYPRLAND_INSTANCE_SIGNATURE=test \
  OMARCHY_LAB_DRM_ROOT="$resize_drm" \
  OMARCHY_LAB_MONITORS_LUA="$resize_monitors" \
  RESIZE_CALLS="$resize_calls" \
  "$resize_helper" --once

rg -q 'output = "Virtual-1", mode = "1600x950"' "$resize_monitors" ||
  fail "display-resize replaces the managed mode"
[[ $(rg -c '^-- BEGIN OMARCHY-LAB-SPICE$' "$resize_monitors") == 1 ]] ||
  fail "display-resize stays idempotent across repeated resizes"
[[ $(tail -n 5 "$resize_monitors" | rg -c '^$') == 1 ]] ||
  fail "display-resize does not accumulate blank lines"
pass "display-resize applies changing virtio modes idempotently"

bytes=$(disk_bytes_from_spec 80G)
[[ $bytes == 85899345920 ]] || fail "80G is 80 GiB in bytes" "$bytes"
read -r boot_start boot_size main_start main_size <<<"$(disk_layout "$bytes")"
[[ $boot_start == 1048576 && $boot_size == 2147483648 && $main_start == 2148532224 && $main_size == 83749765120 ]] ||
  fail "full-disk partition layout matches the ISO configurator" "$boot_start $boot_size $main_start $main_size"
pass "full-disk partition layout matches the ISO configurator"

hash=$(printf '%s' lab | openssl passwd -6 -stdin)
write_cidata_files "$tmpdir/cidata" lab "$hash" omarchy-lab UTC us "$bytes" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI lab@host"

jq -e '.omarchy_install.mode == "full_disk"' "$tmpdir/cidata/user_configuration.json" >/dev/null ||
  fail "cidata is a full-disk install"
jq -e '.omarchy_install.defer_provisioning == false' "$tmpdir/cidata/user_configuration.json" >/dev/null ||
  fail "cidata is not deferred provisioning"
jq -e '.disk_config.device_modifications[0].device == "/dev/vda"' "$tmpdir/cidata/user_configuration.json" >/dev/null ||
  fail "cidata targets the virtio disk"
jq -e 'has("disk_encryption") | not' "$tmpdir/cidata/user_configuration.json" >/dev/null &&
  jq -e '.disk_config | has("disk_encryption") | not' "$tmpdir/cidata/user_configuration.json" >/dev/null ||
  fail "cidata does not request LUKS"
jq -e '.custom_commands[] | select(test("NOPASSWD"))' "$tmpdir/cidata/user_configuration.json" >/dev/null ||
  fail "cidata enables passwordless sudo"
jq -e '.custom_commands[] | select(test("Autologin"))' "$tmpdir/cidata/user_configuration.json" >/dev/null ||
  fail "cidata enables SDDM autologin"
jq -e '.custom_commands[] | select(test("omarchy_resume"))' "$tmpdir/cidata/user_configuration.json" >/dev/null ||
  fail "cidata strips hibernation resume on unencrypted /dev/vda2"
[[ $(<"$tmpdir/cidata/user_encrypt_installation.txt") == false ]] ||
  fail "cidata encryption flag is false"
grep -qx 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI lab@host' "$tmpdir/cidata/authorized_keys" ||
  fail "cidata carries the lab SSH key"
jq -e --arg hash "$hash" '.users[0].username == "lab" and .users[0].sudo == true and .users[0].enc_password == $hash' \
  "$tmpdir/cidata/user_credentials.json" >/dev/null ||
  fail "cidata credentials match the lab user"
pass "cidata is an unencrypted autologin lab install"

wan=$(ufw_rule_specs wlp9s0)
printf '%s\n' "$wan" | rg -q "to any port 67" || fail "UFW specs allow DHCP to any"
printf '%s\n' "$wan" | rg -q "out on wlp9s0" || fail "UFW specs forward only to the uplink"
if printf '%s\n' "$wan" | rg -q '^allow in on virbr0$'; then
  fail "UFW specs must not allow every port on virbr0"
fi
pass "UFW specs stay scoped to DHCP, DNS, and NAT"

url=$(iso_url 4.0.2)
[[ $url == "https://iso.omarchy.org/omarchy-4.0.2.iso" ]] || fail "ISO URL is versioned on iso.omarchy.org" "$url"
pass "ISO URL is versioned on iso.omarchy.org"

args=$(virt_install_args 16384 8 /var/lib/libvirt/images/omarchy-4.0.2.iso /var/lib/libvirt/images/omarchy-lab.base.qcow2 /var/lib/libvirt/images/omarchy-lab.cidata.iso | tr '\0' '\n')
printf '%s\n' "$args" | rg -qx -- '--connect' || fail "virt-install pins qemu:///system"
printf '%s\n' "$args" | rg -q 'qemu:///system' || fail "virt-install uses the system URI"
printf '%s\n' "$args" | rg -q 'OVMF_CODE.4m.fd' || fail "virt-install boots OVMF"
if printf '%s\n' "$args" | rg -q "$HOME/"; then
  fail "virt-install must not point at files under HOME"
fi
pass "virt-install args stay in the libvirt image pool"

block=$(ssh_config_block lab)
printf '%s\n' "$block" | rg -q '^Host omarchy-lab$' || fail "SSH config defines Host omarchy-lab"
printf '%s\n' "$block" | rg -q 'omarchy-lab-vm ip' || fail "SSH config looks up the current lease"
printf '%s\n' "$block" | rg -q 'StrictHostKeyChecking no' || fail "SSH config allows rotating guest host keys"
printf '%s\n' "$block" | rg -q 'UserKnownHostsFile /dev/null' || fail "SSH config does not persist rotating guest host keys"
pass "SSH config uses a ProxyCommand against the current lease"

mkdir -p "$HOME/.ssh"
cat >"$HOME/.ssh/config" <<'EOF'
Host omarchy-lab
  HostName 192.168.122.202
  User lab
  IdentityFile ~/.ssh/omarchy-lab

# BEGIN OMARCHY-LAB-VM
Host omarchy-lab
  User lab
# END OMARCHY-LAB-VM
EOF
write_ssh_config lab
host_count=$(grep -c '^Host omarchy-lab$' "$HOME/.ssh/config" || true)
((host_count == 1)) || fail "write_ssh_config leaves a single Host omarchy-lab" "count=$host_count"
grep -q '192.168.122.202' "$HOME/.ssh/config" && fail "write_ssh_config drops the leftover HostName"
pass "write_ssh_config replaces leftover Host omarchy-lab stanzas"

touch "$HOME/.ssh/omarchy-lab" "$HOME/.ssh/omarchy-lab.pub" "$HOME/.ssh/omarchy-lab.known_hosts"
remove_ssh_artifacts
[[ ! -f $HOME/.ssh/omarchy-lab && ! -f $HOME/.ssh/omarchy-lab.pub && ! -f $HOME/.ssh/omarchy-lab.known_hosts ]] ||
  fail "remove deletes the lab key pair and known_hosts"
grep -q '^Host omarchy-lab$' "$HOME/.ssh/config" && fail "remove deletes Host omarchy-lab"
pass "remove wipes lab SSH keys and config"
