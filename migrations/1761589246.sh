#!/usr/bin/env bash
echo "Install NetworkManager from official repos"

if omarchy-pkg-present networkmanager-iwd; then
  omarchy-pkg-drop networkmanager-iwd
fi

omarchy-pkg-add networkmanager

