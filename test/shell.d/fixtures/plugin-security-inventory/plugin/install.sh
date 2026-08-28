#!/bin/bash

if [[ -n ${INVENTORY_EXECUTION_MARKER:-} ]]; then
  printf 'executed\n' >"$INVENTORY_EXECUTION_MARKER"
fi

sudo pacman -S example-package
