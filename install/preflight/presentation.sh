#!/bin/bash

yay -S --noconfirm --needed gum python-terminaltexteffects python-gobject

# python-gobject installed further down the line but it is missing at 
# somepoint in between step 1 and 3.
