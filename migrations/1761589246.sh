#!/usr/bin/env bash
echo "Install NetworkManager from official repos"

if omarchy-pkg-present networkmanager-iwd; then
  omarchy-pkg-drop networkmanager-iwd
fi

if omarchy-pkg-present networkmanager-git; then
  omarchy-pkg-drop networkmanager-git
fi

omarchy-pkg-add networkmanager
