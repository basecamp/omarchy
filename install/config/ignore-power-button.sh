#!/bin/bash

#Disable shutting system down on power button to bind it to power menu afterwards
sed -i 's/.*HandlePowerKey=.*/HandlePowerKey=ignore/' /etc/systemd/logind.conf