# Security

Omarchy takes security extremely seriously. This is meant to be an operating system that you can use to do _Real Work_ in the _Real World_. Where losing a laptop can't lead to a security emergency. So here's what we do:

1. *Full-disk encryption is mandatory*: This is the most important step to securing the physical protection of your data. If your computer is lost or stolen, the data is fully encrypted using standard LUKS (Linux Unified Key Setup).
2. *Firewall is enabled by default*: All incoming traffic is blocked by default except for port 53317 for [LocalSend](https://localsend.org/). Even ssh is off until you turn it on via _Setup > Security > SSHD_, which opens port 22 (rate limited against brute force) as part of the setup. We even lock down Docker access using the [ufw-docker](https://github.com/chaifeng/ufw-docker) setup to prevent that your containers are accidentally exposed to the world.
3. *Arch always have the latest updates*: Arch, the underlying distro that Omarchy is built on, is a rolling distribution. This means that any security vulnerability that's discovered and patched in any package is quickly available for install using `omarchy-update`. You're always running the latest, most secure versions of everything that way.
4. *Omarchy maintains its own packages and mirror*: Omarchy only relies on packages from Arch's own core/extra/multilib repositories and its own Omarchy Package Repository by default. You can install software directly from AUR, but the base install doesn't — only a few optional installs, like the third-party browsers, pull from the AUR.
5. *Cloudflare protects us from DDoS*: All the Omarchy distribution infrastructure — the ISOs, the Omarchy packages, the Arch mirror — is protected behind Cloudflare's formidable DDoS shield and hosted on their CDN. This provides superb availability.

## Changing your passwords

You have two passwords on an encrypted install: the one that unlocks the drive at boot, and the one you log in and `sudo` with. Both can be changed under _Update > Password_ in the Omarchy menu — _Drive Encryption_ for the first, _User_ for the second. Changing the drive password asks for the current one first, so have it handy. A child install has a third, the parent password, under _Update > Password > Parent_; see below.

## Child installs

Pick _Child_ at the installer's first question and the machine is set up for a kid with two passwords. The **kid password** is the account password: it logs in, unlocks the screen, and unlocks the disk at boot. The **parent password** is root's password, and it is what every privileged path asks for: `sudo`, system prompts, _Update > Omarchy_, every _Install_ and _Remove_ entry, the Windows VM and the Docker TUI, _Setup > Reset Computer_, passwordless sudo, the DNS toggle, and the timezone menu. The kid's account is not an administrator: it is kept out of the `wheel` group on purpose, so nothing that trusts that group reaches it, and _Setup > Security > Passwordless Sudo_ and _Sudoless Docker_, which would hand the account root without a password, are not offered on a child install. Everything that never needed root is the kid's to use: Bluetooth, themes, screenshots, printing, the apps, and the Wi-Fi networks the machine already knows.

Both passwords unlock the disk, and both open the lock screen and the login screen, so a parent can get into the kid's session, locked or logged out, without asking for the kid's password; the login is the kid's account either way. One limit: ten wrong tries lock the kid's account for two minutes, and during those two minutes the parent password waits too. If the kid forgets theirs, boot with the parent password and reset it from a terminal with `sudo passwd <kid>`, which asks for the parent password first. The kid can change their own login password under _Update > Password > User_ at any time; that does not change the disk password, same as on any install.

Joining a new Wi-Fi network, or changing one, asks for the parent password as well: that is a system setting, and NetworkManager only waves it through for administrators. When the kid needs to join a network alone, at school say, run `sudo omarchy-parent wifi kid`; `sudo omarchy-parent wifi parent` puts the prompt back, and `sudo omarchy-parent wifi` shows the setting. The choice lives as `wifi=` in `/etc/omarchy/parent.conf`, which a parent can also edit by hand and apply with `sudo omarchy-parent apply --user <kid>`. Either way, connecting to a network the machine knows, scanning, and the Wi-Fi switch never ask, and the DNS toggle keeps asking.

Change the parent password under _Update > Password > Parent_, or with `sudo omarchy-parent password` in a terminal. That changes root's password, not the disk slot that goes with it: to rotate that as well, run _Update > Password > Drive Encryption_ and type the old parent password when it asks for the current one.

Two things to know. `sudo` remembers a password for a few minutes in the terminal it was typed in, and system prompts remember an authorization for a similar spell, so close the terminal when you are done administering. And the split protects the running system, not the hardware: someone with a live USB and the kid's disk password can reset root's password from outside, so on a kid's laptop set a BIOS password and lock the boot order. A child install does not filter the web on its own; that is a separate layer.

Fingerprint unlock still works for the kid at the lock screen, but `sudo` and system prompts keep asking for the parent password, and FIDO2 setup is not offered because it only ever covered those two. Child installs also close the text consoles behind Ctrl+Alt+F2 through F6, so the lock screen is the only way back into a locked session; `sudo omarchy-parent tty on` reopens them.

## Passing on a machine you've already used

If you're handing your machine over to someone else, you don't have to reinstall it. Run _Setup > Reset Computer_ in the Omarchy menu, type `reset` to confirm, and reboot. That wipes every user account and everything in `/home`, throws away all the packages and system changes you made since installation, and clears the machine's identity — network connections, host keys, and all. What comes back up is the setup wizard from the first boot, ready for its new owner to enter their own name, password, and encryption password.

It works by restoring the baseline snapshot the installer takes, so it's only available on machines installed from the Omarchy ISO. And on a drive without encryption, a reset is deletion rather than a secure erase, so if the data was sensitive, do a fresh install instead.

## Passwordless sudo

Sometimes you want `sudo` to stop asking, most often when an AI agent is doing a long stretch of system work for you. _Setup > Security > Passwordless Sudo_ turns that off for 15 minutes and then puts it back automatically. Run it again before the timer runs out to end it early, and pass your own number of minutes with `omarchy-sudo-passwordless 30` if 15 isn't enough.

Be clear-eyed about this one: while it's on, anything running as your user can do anything as root without being asked. That's the whole point, and it's also the whole risk.

## Signing Keys

The public key for all ISO signatures and Omarchy repo package is `40DFB630FF42BCFFB047046CF0134EE680CAC571` ([verify at openpgp.org](https://keys.openpgp.org/search?q=pkgs%40omarchy.org)). The `omarchy/omarchy-keyring` package contains this as well and will be used to rollout any potential updates seamlessly.

You can find the signature for any ISO release by adding .sig to the URL. Like https://iso.omarchy.org/omarchy-x.x.x.iso.sig.
