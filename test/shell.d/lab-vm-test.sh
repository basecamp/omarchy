#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

lab_vm="$ROOT/bin/omarchy-lab-vm"
lab_rules="$ROOT/default/hypr/apps/lab-vm.lua"
menu="$ROOT/default/omarchy/omarchy-menu.jsonc"

[[ -x $lab_vm ]] || fail "omarchy-lab-vm is executable"
pass "omarchy-lab-vm is executable"

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
rg -q 'virt-viewer --connect .* --attach --reconnect' "$lab_vm" ||
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
rg -q 'lab-vm.desktop' "$menu" || fail "menu presence check looks at the lab desktop entry"
pass "menu wires Install/Remove > Lab"

tmpdir=$(mktemp -d)
export HOME="$tmpdir/home"
mkdir -p "$HOME"
trap 'rm -rf "$tmpdir"' EXIT

# shellcheck disable=SC1090
source "$lab_vm"

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
