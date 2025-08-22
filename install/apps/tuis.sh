#!/bin/bash

if [ -z "$OMARCHY_BARE" ]; then
  omarchy-tui-install "Disk Usage" "bash -c 'dust; read -n 1 -s'" https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/qdirstat.png
fi
