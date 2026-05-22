# Run before limine-snapper.sh so the resume hook + cmdline drop-ins are in
# place before limine-snapper performs the final Limine UKI build. The
# --no-rebuild flag tells hibernation setup to only write config here.
omarchy-hibernation-setup --force --no-rebuild
