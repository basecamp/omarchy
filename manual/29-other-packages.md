# Other Packages

Arch has an amazing wealth of packages available for almost any type of software between the official repository and the Arch User Repository (AUR).

It couldn't be easier to use either. You install a new Arch package by going to _Install > Package_ in the Omarchy menu (`Super + Space`) and typing the package you want. It'll automatically fuzzy filter the list of all packages. (You can also do it manually using `omarchy pkg add [package]` in the terminal).

You can do the same with AUR, just use _Install > AUR_. Just remember that the AUR isn't vetted by the Arch team. It's like RubyGems or npm. Anyone can upload.

If you want to remove a package, you can use _Remove > Package_ from the Omarchy menu. It'll remove package, config files, and dependencies. (You can also do it manually using `omarchy pkg drop [package]`).

## AppImages

Some software is only published as an [AppImage](https://appimage.org/): a single executable file that carries the whole app inside it, with no package to install. Omarchy can turn one into a real app for you. Download the `.AppImage` file, then go to _Install > AppImage_ in the Omarchy menu (`Super + Space`) and pick it. Omarchy files it away under `~/Applications`, lifts the app's own name and icon out of the image, and gives it a launcher, so it shows up in the app launcher (`Super + Space`) like anything else. (You can also do it manually using `omarchy appimage install [path]`.)

To get rid of one, use _Remove > AppImage_ in the Omarchy menu. That deletes the launcher, the icon, and the image itself, so nothing is left behind.
