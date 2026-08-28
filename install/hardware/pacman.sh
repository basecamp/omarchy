# Hardware-specific pacman repository extensions that must survive the final
# pacman.conf restore.
#
# The t2linux repository publishes no package signatures today, and the
# database signature it does publish is stale (it verifies as BAD against the
# current database), so full enforcement would refuse every T2 package and
# break the install. The stanza below arms verification as far as the current
# upstream state allows instead of leaving it off outright:
#
# - PackageOptional verifies any package that carries a signature the moment
#   upstream starts signing, while still accepting the unsigned packages
#   shipped today. A signature that is present but invalid is rejected, so an
#   already-imported key cannot be walked past with a bad signature. It does
#   NOT prevent signature stripping: an attacker who controls the repository
#   can simply stop publishing signatures and pacman accepts the unsigned
#   result. Stripping is only excluded once upstream signs consistently and
#   this policy tightens to PackageRequired.
# - DatabaseNever skips the stale database signature, which a plain Optional
#   would find and reject.
#
# The pinned t2linux signing key (upstream: Noa Himesaka
# <himesaka@noa.codes>) is imported and locally signed so those future
# signatures verify. Residual risk until upstream signs its packages: a
# compromise of the arch-mact2 repository or its delivery path is root code
# execution on T2 machines. That exposure is disclosed to the Omarchy
# security contact and needs an upstream fix (signing the repository); this
# stanza is the strongest stance the current upstream state permits.
t2_pacman_conf=${OMARCHY_T2_PACMAN_CONF:-/etc/pacman.conf}
t2_signing_key=8BE1FEE14302371DEF6F910A0E5877AC225D1980

if lspci -nn | grep "106b:180[12]" >/dev/null; then
  # Fresh installs append the armed stanza; installs that predate this change
  # already carry [arch-mact2] with SigLevel = Never and are reconciled in
  # place instead of skipped.
  if grep -q '^SigLevel = Never$' "$t2_pacman_conf"; then
    if pacman-key --recv-keys "$t2_signing_key" --keyserver keyserver.ubuntu.com &&
       pacman-key --lsign-key "$t2_signing_key"; then
      sed -i 's/^SigLevel = Never$/SigLevel = PackageOptional DatabaseNever/' "$t2_pacman_conf"
    else
      echo "Could not import the pinned t2linux signing key ($t2_signing_key); the arch-mact2 repository stays unverified." >&2
    fi
  elif ! grep -q '^\[arch-mact2\]' "$t2_pacman_conf"; then
    if ! pacman-key --recv-keys "$t2_signing_key" --keyserver keyserver.ubuntu.com; then
      echo "Could not import the pinned t2linux signing key ($t2_signing_key); refusing to enable the arch-mact2 repository unverified." >&2
      exit 1
    fi
    pacman-key --lsign-key "$t2_signing_key"

    cat >> "$t2_pacman_conf" <<'EOF'

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = PackageOptional DatabaseNever
EOF
  fi
fi
