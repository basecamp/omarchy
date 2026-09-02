# Other Packages

Arch has an amazing wealth of packages available for almost any type of software between the official repository and the Arch User Repository (AUR).

It couldn't be easier to use either. You install a new Arch package by going to _Install > Package_ in the Omarchy menu (`Super + Space`) and typing the package you want. It'll automatically fuzzy filter the list of all packages. (You can also do it manually using `omarchy pkg add [package]` in the terminal).

You can do the same with AUR, just use _Install > AUR_. Omarchy opens the complete build recipes and available build-file changes in a blocking terminal viewer, then requires you to confirm the transaction before it proceeds. The AUR isn't vetted by the Arch team, anyone can upload, and a review does not make its executable build recipes safe or isolate them from your files. Only install an AUR package when you understand and trust what it builds.

If you want to remove a package, you can use _Remove > Package_ from the Omarchy menu. It'll remove package, config files, and dependencies. (You can also do it manually using `omarchy pkg drop [package]`).
