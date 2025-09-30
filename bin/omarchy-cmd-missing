#!/bin/bash

for cmd in "$@"; do
  if ! command -v "$cmd" &>/dev/null; then
    exit 0
  fi
done

exit 1
