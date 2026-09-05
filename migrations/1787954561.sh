echo "Allow IGMP so multicast group queries stop flooding the firewall log"

# Omarchy's deny-incoming policy has no exception for IGMP, so ufw drops and
# logs every multicast group query the router sends. The default query interval
# is 125 seconds, which is thousands of log entries a day on an ordinary LAN.
# They evict everything else from the kernel ring buffer and leave dmesg useless
# for diagnosing real problems. A host that never answers those queries can also
# be pruned from multicast by a switch doing IGMP snooping, which breaks mDNS and
# LocalSend discovery.
#
# Machine-wide, but self-detecting: a second user's rerun finds the rule already
# added and no-ops, so no marker file is needed.
if ! sudo ufw show added | grep -q "allow-igmp-multicast"; then
  sudo ufw allow in proto igmp to 224.0.0.0/4 comment 'allow-igmp-multicast'
fi
