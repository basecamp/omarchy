echo "Ignore UPower critical sleep so the shell can act on live remaining energy"

# UPower Auto/Sleep keys off DisplayDevice / the EC fuel gauge. On dual-battery
# ThinkPads that cliff (40% → 6% in a minute) it suspends while live watt-hours
# are still well above 2%. omarchy.battery now warns at 10% and acts at 2% using
# live remaining energy; Ignore stops the daemon from racing that path.
# Ignore is marked "risky" in UPower.conf and needs AllowRiskyCriticalPowerAction.

conf=/etc/UPower/UPower.conf
[[ -r $conf ]] || exit 0

if grep -q '^CriticalPowerAction=Ignore$' "$conf" &&
  grep -q '^AllowRiskyCriticalPowerAction=true$' "$conf"; then
  exit 0
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
python3 - "$conf" "$tmp" <<'PY'
import sys

src, dest = sys.argv[1], sys.argv[2]
out = []
for line in open(src):
    if line.startswith("AllowRiskyCriticalPowerAction="):
        out.append("AllowRiskyCriticalPowerAction=true\n")
    elif line.startswith("CriticalPowerAction="):
        out.append("CriticalPowerAction=Ignore\n")
    else:
        out.append(line)
open(dest, "w").writelines(out)
PY

sudo install -m 644 "$tmp" "$conf"
if omarchy-cmd-present systemctl; then
  sudo systemctl try-restart upower.service || true
fi
