echo "Enable SSD TRIM on LUKS-encrypted drives"

# Without allow-discards, dm-crypt silently drops all TRIM commands,
# causing write amplification and reduced SSD lifespan.
# See: https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD)

if lsblk --noheadings -o TYPE | grep -q "crypt"; then
  for dev in $(lsblk --noheadings -o NAME,TYPE | awk '$2=="crypt" {print $1}'); do
    if ! sudo cryptsetup luksDump /dev/mapper/$dev 2>/dev/null | grep -q "allow-discards"; then
      echo "Enabling allow-discards on /dev/mapper/$dev"
      sudo cryptsetup --allow-discards --persistent refresh $dev
    fi
  done

  chrootable_systemctl_enable fstrim.timer
fi
