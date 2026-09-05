# Security

Omarchy takes security extremely seriously. This is meant to be an operating system that you can use to do _Real Work_ in the _Real World_. Where losing a laptop can't lead to a security emergency. So here's what we do:

1. *Full-disk encryption is mandatory*: This is the most important step to securing the physical protection of your data. If your computer is lost or stolen, the data is fully encrypted using standard LUKS (Linux Unified Key Setup).
2. *Firewall is enabled by default*: All incoming traffic is blocked by default except for port 53317 for [LocalSend](https://localsend.org/). Even ssh is off until you turn it on via _Setup > Security > SSHD_, which opens port 22 (rate limited against brute force) as part of the setup. We even lock down Docker access using the [ufw-docker](https://github.com/chaifeng/ufw-docker) setup to prevent that your containers are accidentally exposed to the world.
3. *Arch always have the latest updates*: Arch, the underlying distro that Omarchy is built on, is a rolling distribution. This means that any security vulnerability that's discovered and patched in any package is quickly available for install using `omarchy-update`. You're always running the latest, most secure versions of everything that way.
4. *Omarchy maintains its own packages and mirror*: Omarchy only relies on packages from Arch's own core/extra/multilib repositories and its own Omarchy Package Repository by default. You can install software directly from AUR, but the base install doesn't — only a few optional installs, like the third-party browsers, pull from the AUR.
5. *Cloudflare protects us from DDoS*: All the Omarchy distribution infrastructure — the ISOs, the Omarchy packages, the Arch mirror — is protected behind Cloudflare's formidable DDoS shield and hosted on their CDN. This provides superb availability.

## Changing your passwords

You have two passwords on an encrypted install: the one that unlocks the drive at boot, and the one you log in and `sudo` with. Both can be changed under _Update > Password_ in the Omarchy menu — _Drive Encryption_ for the first, _User_ for the second. Changing the drive password asks for the current one first, so have it handy.

## Passing on a machine you've already used

If you're handing your machine over to someone else, you don't have to reinstall it. Run _Setup > Reset Computer_ in the Omarchy menu, type `reset` to confirm, and reboot. That wipes every user account and everything in `/home`, throws away all the packages and system changes you made since installation, and clears the machine's identity — network connections, host keys, and all. What comes back up is the setup wizard from the first boot, ready for its new owner to enter their own name, password, and encryption password.

It works by restoring the baseline snapshot the installer takes, so it's only available on machines installed from the Omarchy ISO. And on a drive without encryption, a reset is deletion rather than a secure erase, so if the data was sensitive, do a fresh install instead.

## Passwordless sudo

Sometimes you want `sudo` to stop asking, most often when an AI agent is doing a long stretch of system work for you. _Setup > Security > Passwordless Sudo_ turns that off for 15 minutes and then puts it back automatically. Run it again before the timer runs out to end it early, and pass your own number of minutes with `omarchy-sudo-passwordless 30` if 15 isn't enough.

Be clear-eyed about this one: while it's on, anything running as your user can do anything as root without being asked. That's the whole point, and it's also the whole risk.

## Managed accounts

A managed account is a separate, non-administrator login that can reach only websites you approve. This is useful for a child's account: the restriction applies to every network client under that Linux user, not only Chromium, so installing another browser, changing DNS, using QUIC, or running `curl` does not bypass it.

Create one from _Setup > Security > Managed Accounts > Add Account_, or from a terminal:

```bash
omarchy managed add kid khanacademy.org https://school.example/lessons
```

The menu asks for the login name, the initial allowed websites, and the account's login password. Separate multiple websites with spaces. New logins receive a minimal desktop from Omarchy's shipped defaults without copying private files from the administrator or running the developer-oriented first-login setup. Omarchy disables automatic administrator login when the first managed account is added, so after logging out or rebooting you can choose between the administrator and managed accounts at the login screen.

The allowlist is made of website hosts. Pasting a URL is convenient, but `https://school.example/lessons` becomes `school.example` and includes its subdomains. HTTPS encrypts the path after the host, and Omarchy deliberately does not install a certificate to intercept it. Modern sites often load sign-in pages, video, fonts, or other assets from additional hosts; add those hosts when a page needs them.

To change an existing account, use _Allow Websites_, _Remove Websites_, or _View Websites_ in the same _Managed Accounts_ menu. The first two let you choose the managed account before entering one or more websites.

```bash
omarchy managed allow kid accounts.example school-cdn.example
omarchy managed deny kid school-cdn.example
omarchy managed list kid
```

Under the hood, each managed account gets its own loopback-only Squid proxy and a root-owned allowlist. An nftables output rule tied to that account's numeric user ID rejects every other network connection, including local-network destinations. The administrator account remains unrestricted. Squid is installed from the official Arch repositories the first time this feature is used.

To stop restricting an account without deleting its files:

```bash
omarchy managed remove kid
```

This first version intentionally requires a separate administrator account. Do not give the managed user `sudo`, `wheel`, `docker`, or another root-equivalent capability; Omarchy refuses to manage an account that already has one. A future dedicated kids setup could hide the administrator login and make the managed account the only day-to-day surface, while retaining a safe recovery path.

## Signing Keys

The public key for all ISO signatures and Omarchy repo package is `40DFB630FF42BCFFB047046CF0134EE680CAC571` ([verify at openpgp.org](https://keys.openpgp.org/search?q=pkgs%40omarchy.org)). The `omarchy/omarchy-keyring` package contains this as well and will be used to rollout any potential updates seamlessly.

You can find the signature for any ISO release by adding .sig to the URL. Like https://iso.omarchy.org/omarchy-x.x.x.iso.sig.
