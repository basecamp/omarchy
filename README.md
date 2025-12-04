# Omarch-me
Omarch-me is a fork of [Omarchy](https://omarchy.org) by DHH: "a beautiful, modern & opinionated Linux distribution". This fork makes minor modifications to the install scripts that prioritise open-source apps and allow you to choose yourself which default apps to install with the OS.

## The Changes
Omarch-me is exactly the same as Omarchy after the initial installation. During install, the user will be asked if they want all the default Omarchy apps ('Yes' or 'Customise'). If they choose 'Yes', the installation and resulting setup is unchanged from Omarchy.*

If the user instead chooses 'Customise', only basic system apps will be automatically installed (terminal tools, hardware compatibility, system functionality; all open-source). The user then chooses extra apps to install (with Omarchy configurations) from several small lists:

- 'Extra System': Basic functionality that is more obviously user-facing and easy to have opinions on;
- 'Media/Communications': Programs associated with media file viewing or production (and Signal);
- 'Developer': Programs related to software development;
- 'Unfree': Programs which aren't strictly free and open-source.

Depending on installation choices, certain configuration scripts may be skipped. For example, Docker config will not be run to set up permissions and directories for Docker if the `docker` package was not installed. These config scripts can be run later manually if the user changes their mind, but no interface has yet been set up to facilitate doing so.

From there, you can enjoy your customised Omarchy setup without the artefacts of unwanted apps!

*There will still be a prompt about Nvidia proprietary drivers. User can select 'Yes', and all proceeds as normal. I plan to have this depend on the original 'Yes'/'Customise' in the future.

## Installation
Installation of Omarch-me takes the form of a [manual Omarchy install](https://learn.omacom.io/2/the-omarchy-manual/96/manual-installation) using a different `curl` install script after Arch. This hasn't been set up yet; gimme a couple days.

## The Future
Updates to Omarchy scripts will be vetted and merged from upstream according to the principles:

- There will always be an open-source option available;
- It's your computer, and you decide what will run on it.

In all fairness to Omarchy, not much is needed by way of changes to accomplish this.

## License

Omarch-me is released under the [MIT License](https://opensource.org/licenses/MIT).
