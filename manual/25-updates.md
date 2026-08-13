# Updates

Omarchy and your packages are kept up to date via _Update > Omarchy_ in the Omarchy menu (`Super + Alt + Space`).

This pulls [the latest Omarchy code and configs](https://github.com/basecamp/omarchy/releases), runs any pending migrations to get your system in sync with the latest, and updates all system packages from the [Omarchy Arch Mirror](https://github.com/omacom-io/omarchy-mirror), [Omarchy Package Repository](https://github.com/omacom-io/omarchy-pkgs), and [AUR](https://aur.archlinux.org/) (if you have installed any AUR packages).

When new releases are made, a circle arrow icon will appear to the right of your clock. Click it and the update process will start.

![screenshot-2025-09-28_19-06-08.png](https://learn.omacom.io/u/screenshot-2025-09-28_19-06-08-yZI06N.png)

### Four channels

Omarchy is updated along four channels: stable, RC, edge, and dev. New installations start on the stable channel, which tracks the [official releases](https://github.com/basecamp/omarchy/releases/), as well as the [stable Omarchy Arch mirror](https://github.com/omacom-io/omarchy-mirror) that's running one month behind the latest, so we can catch any new incompatibilities that require config changes before they cause problems for people.

But if you'd like to help spot those potential issues, you can run on the edge channel. That'll keep your Omarchy code tracking official releases, but lets you update to the latest Arch packages as soon as they're available. You should only do this if you're experienced with Linux, and know how to recover a system that has problems.

Before any new major release, we'll be doing final validation using the RC channel. If you're interested in helping with final polishing, come hang out in #omarchy-release-candidates on the Discord.

Finally, there's the dev channel, which gives you the very latest Omarchy code changes and the edge packages. You should only use this channel if you're an experienced Linux user, working directly on Omarchy, and willing to tolerate breakage.

You can switch between channels using _Update > Channel_ from the Omarchy menu.

### Warning about direct pacman/yay updates

If you're already familiar with Arch, you might be tempted to just run `pacman -Syu` or `yay -Syu` yourself, but if you do that, you run the risk that you'll miss updates to the configuration files needed to support newer versions of libraries or tools. So it's best to stick with `Update > Omarchy`, so you're sure that any migrations are run together with new packages.

### Rolling back bad updates

If you ever have a problem after doing an update, you can rollback your system to the snapshot taken before the update. Just restart and pick the snapshot in the boot loading menu from before you started the update.

![omarchy-bootloader.png](https://learn.omacom.io/u/omarchy-bootloader-EVTCUU.png)

If somehow your configuration files have been corrupted, you can also perform an Omarchy reinstall using `omarchy reinstall` in the terminal. This will restore your Omarchy installation to the latest release, put you on stable and downgrade any packages, and reset all the configuration files. Note that all your user config changes to the Omarchy defaults will be overwritten doing this!
