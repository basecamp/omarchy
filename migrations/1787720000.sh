# Reconcile existing T2 installs whose arch-mact2 stanza predates signature
# arming. Fresh installs get the armed stanza from install/hardware/pacman.sh;
# this covers machines that already carry SigLevel = Never and whose normal
# update path runs migrations rather than the hardware installer.

arch_mact2_never='SigLevel = Never'
t2_signing_key=8BE1FEE14302371DEF6F910A0E5877AC225D1980

if grep -q '^\[arch-mact2\]' /etc/pacman.conf 2>/dev/null &&
   grep -q "^${arch_mact2_never}$" /etc/pacman.conf; then
  # A failed key import leaves the machine exactly as it was: the stanza keeps
  # working as it always has, and a later migration retry can import the key.
  # Refusing to transact would break a working T2 machine for no immediate
  # gain, because packages are unsigned either way.
  if sudo pacman-key --recv-keys "$t2_signing_key" --keyserver keyserver.ubuntu.com &&
     sudo pacman-key --lsign-key "$t2_signing_key"; then
    sudo sed -i "s/^${arch_mact2_never}$/SigLevel = PackageOptional DatabaseNever/" /etc/pacman.conf
  else
    echo "Could not import the pinned t2linux signing key; the arch-mact2 repository stays unverified." >&2
  fi
fi
