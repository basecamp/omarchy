# Unattended Installs

The Omarchy ISO can install itself with nobody at the keyboard. If the installer finds a second drive labeled `cidata` carrying its configuration files, it copies them off, skips the setup wizard entirely, and reboots into the finished system on its own. No special ISO build, no extra boot menu entry — with no such drive attached, nothing changes and you get the normal wizard.

This makes Omarchy great as a base image for disposable dev environments: create a VM in Proxmox or with Packer, boot it, walk away, SSH in. `cidata` is the cloud-init `NoCloud` label, so all the common virtualization tooling already knows how to attach such a drive.

## The configuration files

The files are exactly what the installer's own wizard writes, so the easiest way to get a starting set is to run one interactive install (in a VM, say) and copy what it wrote into `/root`:

| File | Required | Purpose |
|------|----------|---------|
| `user_configuration.json` | Yes | Disk, hostname, timezone, keyboard |
| `user_credentials.json` | Yes | Username and password hash |
| `user_full_name.txt` | No | Git full name |
| `user_email_address.txt` | No | Git email |
| `user_encrypt_installation.txt` | No | `true` when the configuration carries a `disk_encryption` block |
| `authorized_keys` | No | SSH public keys, one per line |
| `tailscale_authkey` | No | Tailscale auth key for joining your tailnet on first boot |

Generate the password hash for `user_credentials.json` with `openssl passwd -6 "yourpassword"`.

You can also drop in an empty file named `defer-provisioning` in place of `user_credentials.json`. That runs the same [prepare-for-another-owner install](02-getting-started.md) you can trigger interactively: the machine installs with no personal details, and whoever boots it first picks their keyboard and creates their user. That's the mode for imaging rigs, where the drive shouldn't carry anyone's credentials at all.

## SSH access

When `authorized_keys` is present, the install sets the keys up as the user's `~/.ssh/authorized_keys`, enables `sshd`, and opens the firewall for it. (A stock Omarchy install ships openssh with the service disabled and the port closed, so an unattended machine would otherwise be unreachable.) The install only adds your keys — it doesn't loosen any of the SSH daemon's other authentication settings.

When `tailscale_authkey` is present, the machine joins your tailnet on first boot instead: Tailscale is installed from the ISO's bundled packages, the firewall allows the tailnet interface, and a background job runs the join as soon as the machine actually has network, retrying until it succeeds. Use a reusable, pre-authorized key so one drive image can serve many machines.

## Building the cidata drive

Any filesystem with the right label works. A tiny ISO is the easy way:

```bash
mkdir cidata
cp user_configuration.json user_credentials.json authorized_keys cidata/
genisoimage -output cidata.iso -volid cidata -joliet -rock cidata/
```

Then attach it to the VM alongside the Omarchy ISO. Here's a full Proxmox example:

```bash
qm create 101 --name my-omarchy \
  --bios ovmf --machine q35 --cpu host --cores 4 --memory 8192 \
  --ostype l26 --scsihw virtio-scsi-single \
  --efidisk0 local-lvm:0,efitype=4m,pre-enrolled-keys=0 \
  --scsi0 local-lvm:40,discard=on,iothread=1 \
  --net0 virtio,bridge=vmbr0 --vga virtio --serial0 socket \
  --ide2 local:iso/omarchy.iso,media=cdrom \
  --ide3 local:iso/cidata.iso,media=cdrom \
  --boot order='scsi0;ide2'

qm start 101
```

The boot order lists the disk first on purpose: the empty disk falls through to the ISO on the first boot, and the installed system boots from disk ever after.

## Two caveats

Encrypted unattended installs aren't fully unattended — someone still has to type the LUKS passphrase at the first boot. And the `disk_encryption` block in `user_configuration.json` carries that passphrase in plaintext, so treat a cidata drive built from an encrypted install as the secret it is.
