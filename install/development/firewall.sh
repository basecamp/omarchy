#!/bin/bash

if [[ -z "${OMARCHY_CHROOT_INSTALL:-}" ]]; then
  omarchy-install-firewall
fi
