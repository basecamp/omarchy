echo "Run the WPA handshake in software on Macs with Broadcom Wi-Fi"

# The install-time quirk only reaches machines set up after it shipped, and it
# never covered Macs without a T2 at all, so an existing install on one still
# cannot join a WPA2/WPA3 transition-mode network. See
# install/hardware/apple/fix-brcmfmac-supplicant.sh for the failure it fixes and
# for where this list of brcmfmac PCI IDs comes from.
dmi_vendor="${OMARCHY_BRCMFMAC_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}"
conf="${OMARCHY_BRCMFMAC_CONF:-/etc/modprobe.d/brcmfmac.conf}"

# Intel Macs only. Apple Silicon Macs report the same vendor and carry two of
# the same PCI IDs, and there this option leaves the machine with no Wi-Fi at
# all (#7439). migrations/1787163407.sh takes it back off the machines this one
# already reached.
[[ $(uname -m) == "x86_64" ]] || exit 0

sys_vendor="$(cat "$dmi_vendor" 2>/dev/null || true)"

if ! lspci -nn | grep "106b:180[12]" >/dev/null &&
  ! { [[ $sys_vendor == Apple* ]] &&
    lspci -nn | grep -E "14e4:(43ba|43bb|43bc|43a3|43dc|4464|4488|4425|4433)" >/dev/null; }; then
  exit 0
fi

# T2 installs already carry this from the installer, so the common case is a
# no-op for the first user and every user after them. Only an active options
# line counts: someone who commented theirs out still needs this.
if [[ -f $conf ]] &&
  grep -Eq '^[[:space:]]*options[[:space:]]+brcmfmac[[:space:]].*feature_disable=0x82000' "$conf"; then
  exit 0
fi

sudo mkdir -p "$(dirname "$conf")"

# Append rather than overwrite, so anything else a user keeps here survives:
# modprobe reads every options line for a module, and nothing else sets
# feature_disable. The leading newline also covers a file that ends without one.
sudo tee -a "$conf" >/dev/null <<'EOF'

# Broadcom's firmware supplicant and authenticator fail the WPA four-way
# handshake on Apple hardware, which surfaces as a rejected password. Disable
# both so wpa_supplicant performs the handshake instead.
options brcmfmac feature_disable=0x82000
EOF

# modprobe only reads this when the module loads. Reloading brcmfmac here would
# drop a Wi-Fi connection that works on the network the user is on right now,
# including the one carrying this update.
omarchy-state set reboot-required
