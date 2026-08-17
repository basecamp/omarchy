echo "Switch mise to the mise-bin package from the Omarchy repo"

# mise-bin carries mise's own release artifacts -- PGO+BOLT-optimized on x86_64,
# glibc-native on both arches -- and takes over from Arch's mise, which it both
# provides and conflicts with.
#
# The swap has to happen in one transaction. Removing mise first breaks
# omarchy-zsh and omarchy-fish, which depend on it; the provides is what keeps
# them satisfied when mise-bin lands in the same transaction that drops mise.
#
# omarchy-pkg-add cannot do that swap: pacman answers its own conflict question
# with No under --noconfirm and fails the whole transaction ("unresolvable
# package conflicts detected"). --ask=4 is that one question, answered yes.

if omarchy-pkg-missing mise-bin; then
  sudo pacman -S --noconfirm --ask=4 mise-bin
fi
