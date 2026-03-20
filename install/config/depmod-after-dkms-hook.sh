sudo install -Dm644 /dev/stdin /etc/pacman.d/hooks/75-depmod-after-dkms.hook <<'EOF'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/updates/dkms/*.ko*
Target = usr/lib/modules/*/extramodules/*.ko*

[Action]
Description = Rebuilding module dependecies after DKMS
When = PostTransaction
Exec = /bin/sh -c 'for d in /usr/lib/modules/*/; do [ -f "${d}modules.order" ] && depmod "$(basename "$d")"; done'
EOF