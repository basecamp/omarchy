#!/bin/bash
sed -i 's/-e btop/-e sh -c '\''btop; exec \$SHELL'\''/g' ~/.local/share/omarchy/default/hypr/bindings.conf ~/.config/hypr/bindings.conf


