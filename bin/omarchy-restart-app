#!/bin/bash

pkill -x $1
setsid uwsm-app -- $1 >/dev/null 2>&1 &
