#!/bin/bash

omarchy-tui-install "Disk Usage" "bash -c 'dust -r; read -n 1 -s'" float https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/qdirstat.png
omarchy-tui-install "Docker" "lazydocker" tile https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/docker.png
omarchy-tui-install "Tailscale" "tsui" tile https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/tailscale-light.png