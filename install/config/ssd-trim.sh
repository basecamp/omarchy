#!/bin/bash

if grep -q 0 /sys/block/*/queue/rotational; then
    echo "Non-rotational device detected → enabling fstrim.timer"
    sudo systemctl enable --now fstrim.timer
else
    echo "No non-rotational device detected → skipping fstrim.timer activation"
fi
