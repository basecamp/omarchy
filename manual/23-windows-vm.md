# Windows VM

Omarchy offers an easy way to run Windows through a Docker VM. You can install it using _Install > Windows_ from the Omarchy menu (`Super + Space`). It takes a while, but you can follow the progress in the browser.

When the installation is complete, you can launch Windows using the app launcher, and that'll give you a RDP connection to your installation. When you close the RDP session, the VM automatically stops again. If you want to get rid of the whole thing, use _Remove > Windows_ from the Omarchy menu. There's no GPU passthrough with this setup, so it's not suitable for gaming or video editing, but it's a great way to run apps like Microsoft Office or whatever else if you absolutely must have that.

The directory `~/Windows` in your home directory is automatically shared with this Windows VM. So you put files there if you want to make them accessible to Windows. The VM does not have access to any other files on your system, so you're safe from malware or viruses on the Linux side.

You can change the resource allocation by editing `~/.config/windows/docker-compose.yml`. You can also edit this file to mount USB devices. See all the options on [the Dockur Windows project](https://github.com/dockur/windows).

The version of Windows installed is 11 Pro. It's unactivated. You will need to activate with your own license key to use all gated features.

 ![windows.png](https://learn.omacom.io/u/windows-bhXSXL.png)
