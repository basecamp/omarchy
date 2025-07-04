if find /sys/bus/usb/devices/ -name "product" -exec grep -l -iE "(fingerprint|biometric|validity|synaptics|elan|upek)" {} \; 2>/dev/null | head -n1; then 
    sudo pacman -S fprintd
fi