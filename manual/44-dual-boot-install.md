# Dual Boot Install

You're able to install Omarchy to a single partition alongside Windows or other installations.

This installation method still comes with LUKS encryption for the partition by default so it's effectively no different than full drive and simply requires free space to be available on the disk.

## Making Space on Windows

To install alongside Windows, type `disk management` in the start menu and select the option for **Create and format hard disk partitions**.

 ![screenshot-2026-06-06_13-37-28.png](https://learn.omacom.io/u/screenshot-2026-06-06_13-37-28-mjjTRj.png)

Find the appropriate partition, right click, and choose **Shrink Volume**.

![screenshot-2026-06-06_13-37-50.png](https://learn.omacom.io/u/screenshot-2026-06-06_13-37-50-xqulDe.png)

 Input the amount you'd like to shrink the volume by. Note that this will be the size of your future Omarchy install inclusive of the boot partition.

 ![screenshot-2026-06-06_13-38-23.png](https://learn.omacom.io/u/screenshot-2026-06-06_13-38-23-bsMeTK.png)

When you're finished, you should see something like this where the 50GB section is where we'll install Omarchy in this example.

 ![screenshot-2026-06-06_13-38-36.png](https://learn.omacom.io/u/screenshot-2026-06-06_13-38-36-LjrgYW.png)

## Installing Omarchy

The install process for Omarchy is effectively the same as normal. After you select your disk, you'll be given the option of **Free space install**. Select that option to prevent wiping the full disk.

 ![screenshot-2026-08-12_20-21-05.png](https://learn.omacom.io/u/screenshot-2026-08-12_20-21-05-MiHt03.png)

Confirm that everything looks good and wait for the install to finish like normal. This is also where you could elect to install unencrypted (not recommended) just like on a full-drive install.
 ![screenshot-2026-08-12_20-33-49.png](https://learn.omacom.io/u/screenshot-2026-08-12_20-33-49-UX0gZl.png)

## Adding Other Installs to the Bootloader

When you finish your Omarchy install, you'll notice that the Limine bootloader is the default now. With this, you can also add options to Limine for your other installs such as Windows.

In order to do that, run `limine-scan` and follow the prompts to add whichever items you'd like to your limine config. Then when you boot, you'll see your normal options for Omarchy, as well as Windows Boot Manager or others.

## Bitlocker

It's important to note that this install method is not compatible with Bitlocker as it encrypts the entire drive, not just the partition. If you encounter an error stating that Bitlocker is enabled, boot to Windows, go to **Settings -> Privacy & Security -> Device encryption** and toggle Bitlocker off. It may take some time to decrypt the drive.

 ![screenshot-2026-08-12_20-28-27.png](https://learn.omacom.io/u/screenshot-2026-08-12_20-28-27-jdscbY.png)
