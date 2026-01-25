Sync omarchy and dotfiles to the test VM and build.

VM IP: $ARGUMENTS

Steps:
1. Rsync `/home/steven/dev/omarchy/` to the VM at the same path
2. Rsync `/home/steven/dotfiles/` to the VM at the same path
3. SSH to the VM and run `nix flake update omarchy --flake /home/steven/dotfiles`
4. SSH to the VM and run `nh os build /home/steven/dotfiles`

Use the IP provided as $ARGUMENTS. If no IP was given, ask the user for it.
