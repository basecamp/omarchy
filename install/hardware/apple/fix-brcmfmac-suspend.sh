# BCM43602's brcmfmac firmware occasionally fails to reinitialize its message
# ring after suspend/resume: every ioctl times out ("brcmf_msgbuf_query_dcmd:
# Timeout on response for query command", then cascading -5/-12 errors) and
# Wi-Fi stays dead until a reboot. It isn't every cycle -- the driver
# sometimes redoes the firmware download cleanly on resume and sometimes
# doesn't -- which is what makes it read as "Wi-Fi randomly dies after
# sleep" rather than a hard failure. See kernel.org bugzilla #196019 and
# #197977, both open since 2017 with no upstream driver fix.
#
# Forcing a full module unload/reload around every suspend makes the driver
# redo the firmware download it already performs successfully on a cold
# boot, instead of relying on the in-place PCIe resume path that
# intermittently fails.
#
# Same chip family as the four-way-handshake quirk in
# fix-brcmfmac-supplicant.sh: BCM43602 and its single-band variants in
# 2015-2017 Macs (14e4:43ba/43bb/43bc). Scoped to just that family for now --
# the 2018+ chips (BCM4350/4355/4364) and T2-era chips (BCM4377/4378/4387)
# have their own suspend behavior and are already being tracked separately
# (see github.com/basecamp/omarchy/discussions/4695).
if lspci -nn | grep -E "14e4:(43ba|43bb|43bc)" >/dev/null; then
  echo "Detected BCM43602 Wi-Fi; installing suspend/resume firmware-reload workaround"

  mkdir -p /usr/lib/systemd/system-sleep
  cat > /usr/lib/systemd/system-sleep/brcmfmac-suspend.sh <<'EOF'
#!/bin/bash

# Work around a brcmfmac/BCM43602 firmware bug where suspend/resume
# occasionally leaves the wifi message ring uninitialized. See
# install/hardware/apple/fix-brcmfmac-suspend.sh for the full explanation.

case "$1" in
  pre)
    modprobe -r brcmfmac_wcc 2>/dev/null
    modprobe -r brcmfmac 2>/dev/null
    ;;
  post)
    modprobe brcmfmac
    modprobe brcmfmac_wcc 2>/dev/null
    ;;
esac

exit 0
EOF
  chmod 755 /usr/lib/systemd/system-sleep/brcmfmac-suspend.sh
fi
