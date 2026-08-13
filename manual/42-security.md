# Security

Omarchy takes security extremely seriously. This is meant to be an operating system that you can use to do _Real Work_ in the _Real World_. Where losing a laptop can't lead to a security emergency. So here's what we do:

1. *Full-disk encryption is mandatory*: This is the most important step to securing the physical protection of your data. If your computer is lost or stolen, the data is fully encrypted using standard LUKS (Linux Unified Key Setup).
2. *Firewall is enabled by default*: All incoming traffic is blocked by default except for port 53317 for [LocalSend](https://localsend.org/). Even ssh is off until you turn it on via _Setup > Security > SSHD_, which opens port 22 (rate limited against brute force) as part of the setup. We even lock down Docker access using the [ufw-docker](https://github.com/chaifeng/ufw-docker) setup to prevent that your containers are accidentally exposed to the world.
3. *Arch always have the latest updates*: Arch, the underlying distro that Omarchy is built on, is a rolling distribution. This means that any security vulnerability that's discovered and patched in any package is quickly available for install using `omarchy-update`. You're always running the latest, most secure versions of everything that way.
4. *Omarchy maintains its own packages and mirror*: Omarchy only relies on packages from Arch's own core/extra/multilib repositories and its own Omarchy Package Repository by default. You can install software directly from AUR, but the base install doesn't — only a few optional installs, like the third-party browsers, pull from the AUR.
5. *Cloudflare protects us from DDoS*: All the Omarchy distribution infrastructure — the ISOs, the Omarchy packages, the Arch mirror — is protected behind Cloudflare's formidable DDoS shield and hosted on their CDN. This provides superb availability.

## Signing Keys

The public key for all ISO signatures and Omarchy repo package is `40DFB630FF42BCFFB047046CF0134EE680CAC571` ([verify at openpgp.org](https://keys.openpgp.org/search?q=pkgs%40omarchy.org)). The `omarchy/omarchy-keyring` package contains this as well and will be used to rollout any potential updates seamlessly.

You can find the signature for any ISO release by adding .sig to the URL. Like https://iso.omarchy.org/omarchy-x.x.x.iso.sig.
