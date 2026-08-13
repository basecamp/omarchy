# Shell Functions

Omarchy comes with a set of shell functions to simplify common tasks and encapsulate convoluted parameter calls.

## Compression

- `compress [file/dir]`: Create a tar.gz archive from the file/dir.
- `decompress [file.tar.gz]`: Expand a tar.gz file.

## Drives

-  `iso2sd [image.iso]`: Create a bootable drive on an SD card using the referenced iso file and picking the drive interactively.
- `format-drive`: Select an entire disk to format with a single exFAT partition (which works on Windows and macOS too). Be careful!

## SSH Portforwarding

Ideal for doing web development with localhost secure-context privileges against a remote box.

- `fip`: Forward one or more ports from a remote host to localhost via SSH.
- `dip`: Disconnect one or more forwarded ports.
- `lip`: List all active SSH port forwards.

Say you start a dev server on port `3000` on a machine accessible as `nyc-dev`, then you can run `fip nyc-dev 3000` to forward that port, so `localhost:3000` actually reaches `nyc-dev:3000`, but without the need for SSL certificates to establish the secure context needed for testing web sockets or the like.
