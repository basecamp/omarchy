# Omarchy

Turn a fresh Fedora installation into a fully-configured, beautiful, and modern web development system based on Hyprland by running a single command. That's the one-line pitch for Omarchy (adapted from the original Arch version for Omakub). No need to write bespoke configs for every essential tool just to get started or to be up on all the latest command-line tools. Omarchy is an opinionated take on what Linux can be at its best.

**Note**: This version has been adapted for Fedora Linux. The original was designed for Arch Linux.

Read more at [omarchy.org](https://omarchy.org).

Install: wget -qO- https://u11g.com/install | bash

TODOs: Install eza

Graphics Intel: https://fostips.com/hardware-acceleration-video-fedora/?amp=1
Start Zoom:

```
[Desktop Entry]
Name=Zoom Workplace
Comment=Zoom Video Conference
Exec=env QT_QPA_PLATFORM=xcb /usr/bin/zoom %U
Icon=Zoom
Terminal=false
Type=Application
Encoding=UTF-8
Categories=Network;Application;
StartupWMClass=zoom
MimeType=x-scheme-handler/zoommtg;x-scheme-handler/zoomus;x-scheme-handler/tel;x-scheme-handler/callto;x-scheme-handler/zoomphonecall;x-scheme-handler/zoomphonesms;x-sche>
X-KDE-Protocols=zoommtg;zoomus;tel;callto;zoomphonecall;zoomphonesms;zoomcontactcentercall;
Name[en_US]=Zoom Workplace
```

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).
