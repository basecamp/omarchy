# Getting Started

Omarchy is installed using an ISO. It's designed for a dedicated drive, so dual-booting requires two disks in your machine (unless you do a [manual install](38-manual-installation.md) to work around this). The installation will wipe the selected drive and use full-disk encryption, so be sure to take a backup before using an existing drive!

[Download the Omarchy ISO](https://omarchy.org/) first, put it on a USB stick (use [balenaEtcher](https://etcher.balena.io/) on Mac/Windows or [caligula](https://github.com/ifd3f/caligula) on Linux), and boot off the stick.

_You must turn off Secure Boot and/or TPM in the BIOS. You have to turn these off to be able to install Omarchy. They're Microsoft security schemes meant for Windows and Microsoft-affiliated Linux distributions._

Then answer the configuration questions, and confirm them like this:

 ![omarchy-install.png](https://learn.omacom.io/u/omarchy-install-k5Iksv.png)

Then select a drive for your installation, and sit back and watch the installation show go. It takes between 2-10 minutes, depending on the speed of your computer.

 ![omarchy-installed.png](https://learn.omacom.io/u/omarchy-installed-NR1wu1.png)

Now you're ready to Omarchy!

### Use a wired or 2.4ghz keyboard!

The full-disk encryption won't allow you to enter the password from a Bluetooth keyboard at startup. Just like you can't use a Bluetooth keyboard to enter the BIOS on a PC. You'll need a keyboard that either uses a 2.4ghz dongle or a cable (which is much nicer for latency anyway!). I personally love the [Lofree Flow84](https://www.lofree.co/products/lofree-flow-the-smoothest-mechanical-keyboard)!

### No-encryption installations

Omarchy is installed with encryption by default. It's the safe, reasponsible choice for any computer that can possibly be lost or stolen. You don't want anyone with access to your hardware to be able to get your data!

But in special circumstances, like remote Omarchy installs on protected computers or for throw-away installations without sensitive data, you may want to install without encryption. You can hit `Ctrl + C` on the disk formatting confirmation to switch to an encryption-less installation.

### Help if you're stuck

If you get stuck, you can usually find someone willing to help in the _#omarchy-help_ channel on [the community Discord](https://omarchy.org/discord).

### Use manual installation for special needs

If you have special needs, like installing Omarchy onto M-Series MacBooks [Asahi Alarm](https://asahi-alarm.org/) or because you want to try dual-booting on a single drive, you should follow [the instructions for a manual installation](38-manual-installation.md).
