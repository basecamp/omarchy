echo "Give the pre-suspend lock a window it can actually finish in"

# logind's five second default expires while Quickshell is still securing the
# session on lid close, and it suspends regardless. The shipped drop-in raises
# InhibitDelayMaxSec, but logind only reads it on reload.
#
# Reload rather than restart: restarting systemd-logind tears down the session.
sudo systemctl reload systemd-logind >/dev/null 2>&1 || true

# Check the property logind actually enforces, not the reload's exit status: a
# reload that returns success while the drop-in is missing or unparsed leaves
# the old five second window in place. omarchy-system-sleep-lock reads this same
# property at runtime, so it stays correct either way -- the reboot flag is only
# about getting the wider window to take effect.
#
# Both reads have to survive failing: a missing drop-in or an unreachable logind
# is the very condition being tested for, and migrations run under -e.
dropin=/etc/systemd/logind.conf.d/20-inhibit-delay.conf
expected_s=$(sed -n 's/^InhibitDelayMaxSec=//p' "$dropin" 2>/dev/null || true)
effective_us=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
  org.freedesktop.login1.Manager InhibitDelayMaxUSec 2>/dev/null | awk '{print $2}' || true)

if [[ -z $expected_s || $effective_us != $((expected_s * 1000000)) ]]; then
  omarchy-state set reboot-required
fi
