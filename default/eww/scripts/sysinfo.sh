#!/bin/bash
# DedSec HUD -- System information helper for EWW widgets
# Returns JSON with hostname and IP address

hostname_val=$(hostname 2>/dev/null || echo "UNKNOWN")
ip_val=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "OFFLINE")

echo "{\"hostname\": \"$hostname_val\", \"ip\": \"$ip_val\"}"
