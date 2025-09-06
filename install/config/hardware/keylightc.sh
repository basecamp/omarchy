#!/bin/bash

sudo install -m 755 -D -t /usr/bin/ ../../assets/keylightc
sudo install -m 644 -D -t /usr/lib/systemd/system/ ../../assets/keylightc.service

sudo systemctl enable --now keylightc.service