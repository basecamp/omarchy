# Idle-state freeze fix for 2011 MacBook Airs (MacBookAir4,1 / MacBookAir4,2).
#
# The Sandy Bridge CPUs in these machines hard-lock when dropping into deep
# C-states after load: the whole machine freezes (no TTY switch, no SysRq,
# nothing reaches the journal) within seconds-to-minutes of reaching an idle
# desktop. Capping intel_idle at C1 prevents the lockup, at some idle power
# cost on hardware that is otherwise unusable.

if omarchy-hw-match "MacBookAir4,"; then
  mkdir -p /etc/limine-entry-tool.d
  cat > /etc/limine-entry-tool.d/apple-sandy-bridge-idle.conf <<'EOF'
# 2011 MacBook Air (Sandy Bridge) hard-locks when idling into deep C-states
KERNEL_CMDLINE[default]+=" intel_idle.max_cstate=1"
EOF
fi
