# Manual installation

If you can't use the Omarchy ISO, you can do a manual installation using the vanilla arch ISO, archinstall, and following the steps in this guide. This is not something most people should attempt, but if you know what you're doing, and why you're doing it, this is how.

1. [Download the Arch Linux ISO](https://archlinux.org/download/#http-downloads), put it on a USB stick (use [balenaEtcher](https://etcher.balena.io/) on Mac/Windows), and boot off the stick (remember to turn off Secure Boot in the BIOS!).
2. If you're on wifi, start by running `iwctl`, then type `station wlan0 scan`, then `station wlan0 connect <tab>`, pick your network, and enter the password. If you're on ethernet, you don't need this.
3. Run `archinstall` and pick these options (and leave anything not mentioned as-is):

| Section | Option |
| -------- | ------ |
| Mirrors and repositories | Select regions > Your country |
| Disk configuration | Partitioning > Default partitioning layout > Select disk (with space + return) |
| Disk > File system | btrfs (default structure: yes + use compression) |
| Disk > Disk encryption | Encryption type: LUKS + Encryption password + Partitions (select the one) |
| Hostname | Give your computer a name |
| Bootloader | Limine |
| Authentication > Root password | Set yours |
| Authentication > User account | Add a user > Superuser: Yes > Confirm and exit |
| Applications > Audio | pipewire |
| Network configuration | Copy ISO network config |
| Timezone | Set yours |

Beware that you _must setup disk encryption_ to use Omarchy as designed! The setup relies exclusively on disk encryption to secure your device, as it'll auto-login the user after the disk has been decrypted at boot.

Just note that this encryption setup won't allow you to enter the password from a Bluetooth keyboard at startup. Just like you can't use a Bluetooth keyboard to enter the BIOS on a PC. You'll need a keyboard that either uses a 2.4ghz dongle or a cable (which is much nicer for latency anyway!). I personally love the [Lofree Flow84](https://www.lofree.co/products/lofree-flow-the-smoothest-mechanical-keyboard)!

Here's what the disk encryption setup should look like. You need to pick `LUKS`, then set the encryption password, then apply to the partition (this step is crucial or nothing gets encrypted!):

 ![arch-encryption.png](https://learn.omacom.io/u/arch-encryption-urjrDm.png)

Once Arch has been installed, pick reboot, login with the user you just setup, and now you're ready to install Omarchy by running:

`curl -fsSL https://omarchy.org/install | bash`

It'll first ask you to sudo, then shortly thereafter, it'll ask for your name and email address. Those credentials are used to preconfigure git (`git config --global user.name/email`) and set for auto-expansion on `CapsLock Space E` (email) and `CapsLock Space N` (name). After that, it'll run by itself for 5-30 minutes, depending on the speed of your internet connection. When it's all done, it'll ask for your permission to reboot the system.

Now you're ready to Omarchy!
