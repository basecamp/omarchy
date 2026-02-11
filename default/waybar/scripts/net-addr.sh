#!/bin/bash
# DedSec HUD -- Get primary IP address for waybar module
ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "OFFLINE"
