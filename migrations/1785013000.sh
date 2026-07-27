echo "Move zram tuning to a vendor drop-in"

zram_conf="${OMARCHY_ZRAM_CONF:-/etc/systemd/zram-generator.conf}"
zram_dropin="${OMARCHY_ZRAM_DROPIN:-/usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf}"

# The tuning ships as /usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf.
# Drop-ins outrank the main config file, so a leftover /etc copy decides nothing
# and only implies /etc is where zram gets configured.

[[ -f $zram_conf ]] || exit 0

# Only once the replacement is on disk. zram-generator makes no device at all
# when nothing configures one, so until the drop-in lands the /etc copy is the
# only thing standing between this machine and no zram swap. The update pipeline
# installs packages before it runs migrations, but a dev checkout carries
# migrations from a release the installed package does not have yet.
[[ -f $zram_dropin ]] || exit 0

# Package-owned copies go away with their package on upgrade.
pacman -Qo "$zram_conf" &>/dev/null && exit 0

# archinstall writes exactly a [zram0] section with one compression-algorithm
# line. Anything else is a deliberate local override. grep exits 1 on a config
# that sets nothing at all, which omarchy-migrate's -e would take as a failed
# migration and block every migration behind this one.
settings=$(grep -vE '^[[:space:]]*([#;]|$)' "$zram_conf" | tr -d '[:space:]') || true

if [[ -z $settings || $settings =~ ^\[zram0\]compression-algorithm=[[:alnum:]-]+$ ]]; then
  # A refused sudo just leaves the file for next time; tidying is not worth
  # failing the migration chain over.
  sudo rm -f "$zram_conf" || true
else
  echo "Keeping $zram_conf; it has local edits."
  echo "Omarchy's drop-in overrides it. Move your changes to"
  echo "/etc/systemd/zram-generator.conf.d/99-local.conf to keep them in effect."
fi
