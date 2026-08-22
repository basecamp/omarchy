# Backups

Snapshots roll the system back. Backups get your files back. They are different jobs: [system snapshots](47-system-snapshots.md) live on the same disk and skip your home folder entirely, so a dead disk, a stolen laptop, or a folder you deleted last month needs something else.

Run _Setup > Backup_ from the Omarchy menu (or `omarchy setup backup`). Paste the credentials for a storage bucket, save the passphrase, and from then on Omarchy backs up your home folder every hour: only what changed, encrypted before it leaves the machine, and versioned so you can go back to how a file looked last Tuesday.

## Setting it up

The wizard asks for three things:

1. **Where the backups go.** An S3-compatible bucket (Backblaze B2, Cloudflare R2, AWS, Hetzner, Wasabi, MinIO — anything that speaks the protocol), a local disk or NAS folder, or any [restic](https://restic.net) repository URL if you know what you want.
2. **A passphrase.** It encrypts everything before upload. Generate one or bring your own.
3. **Confirmation that you saved the passphrase.** Omarchy writes a recovery card to `~/Omarchy Backup Recovery.txt` with your destination and the restore commands, leaving a blank line for the passphrase to be written in by hand.

Then it runs the first backup while you watch, and only turns on the hourly schedule once that has worked. A backup icon appears in the bar.

**Lose the passphrase and the backups are gone.** Not delayed, not recoverable by support — gone. Nobody but you can read those files, which is the point, and the price. Keep the passphrase somewhere that is not this machine.

## What gets backed up

Your home folder, minus caches and other bytes that regenerate themselves — browser caches, `node_modules`, package manager downloads, thumbnails, the trash. The shipped list is in `$OMARCHY_PATH/default/backup/excludes` and errs towards including things: a backup that skipped what you needed is worse than one that carried something you didn't.

Add your own patterns, one per line, in `~/.config/omarchy/backup/excludes`:

```
Videos/raw-footage
**/*.iso
.local/share/containers
```

Mounted network shares and removable disks are never followed, so a NAS mount in your home folder does not get uploaded to your bucket.

System files are not backed up. Omarchy reinstalls from the ISO in a few minutes, and the things you configured are in your home folder.

## Getting files back

Three ways, depending on what you know:

```bash
omarchy backup restore ~/Documents/taxes.pdf            # into ~/Restored/<timestamp>/
omarchy backup restore ~/Pictures --at 2026-01-15       # as it was on that date
omarchy backup restore ~/Notes --in-place               # put it back where it was
omarchy backup browse                                   # every backup as dated folders
```

Restores land in `~/Restored/<timestamp>/` by default, so a restore never overwrites something you still have. `--in-place` does overwrite, after asking, and copies the current version into `~/Restored/` first — so even an in-place restore you regret is recoverable.

`omarchy backup browse` mounts every backup as a folder tree and opens the file manager on it. Browse to a date, drag out what you want, close the window. Nothing to learn.

## Day to day

The bar icon is the whole interface most of the time: quiet when things are fine, animated while a backup runs, dimmed when paused, and coloured when something needs you. Click it for the panel: when the last backup happened, how big the repository is, a **Back up now** button, **Pause for an hour**, and a way into browsing older versions.

From the terminal:

```bash
omarchy backup status          # what happened, and when
omarchy backup now             # do not wait for the top of the hour
omarchy backup pause 1h        # or: today, until-resumed
omarchy backup resume
omarchy backup snapshots       # every backup this machine has made
omarchy backup log             # what the scheduled runs have been doing
```

Backups skip themselves when they should: while paused, when the laptop is on battery below 20%, when another backup is still running, and — for a local destination — when the disk is not plugged in. A single failed run stays quiet, because café wifi is not news. A full day without a complete backup gets you a notification, repeated weekly until it is fixed.

Old backups are thinned out monthly: 24 hourly, 7 daily, 5 weekly, and 12 monthly are kept. Change those numbers in `~/.config/omarchy/backup/settings` if you want a different shape.

## More than one machine

Point the second machine at the same bucket and it just works: each machine's backups are kept separately, restores default to your own machine's, and nothing is ever merged or synced between them. Give your machines distinct hostnames — that name is how backups are told apart.

The machine you set up first owns the monthly cleanup, so the expensive part of the job does not run on every laptop at once.

Worth knowing: every machine sharing a repository can read all of it. That is what makes the next section possible, and it means one compromised machine exposes the rest. If you want machines isolated from each other, give them separate buckets or prefixes.

## Starting over on a new machine

This is the part that pays for the whole feature. Install Omarchy, run _Setup > Backup_, point it at the same bucket, and give it the passphrase. It finds the backups from your old machine and offers to restore that home folder into this one before anything else happens.

Your files, your configs, your keys, your projects — back where they were, on a machine that is an hour old.

## What this does and does not protect you from

**It protects you from**: a dead disk, a stolen or lost laptop, a folder deleted three weeks ago and missed today, a migration that ate something. Anything where you still have your storage account and your passphrase.

**It does not protect you from** malware running as you, right now. The machine has to hold credentials that can write to — and, to make room, delete from — the repository. Ransomware with your privileges can reach the backups too. Object versioning or object lock on the bucket helps, and is worth setting up if your provider supports it, but it is a per-provider job with its own recovery procedure rather than a checkbox here.

**Running databases, virtual machine disks, and containers** are copied while they are live, so what lands in the backup is a crash-consistent state at best. Stop them, or dump them somewhere in your home folder, if you need better than that.

**Do not put the bucket on a cold-storage or archival tier.** Backups need to read small objects at any moment; archival tiers make that slow, expensive, or impossible, and restic will not tell you until you need a restore.

## Turning it off

```bash
omarchy setup backup --remove
```

That stops the schedule, removes the widget, and deletes the local credentials. Your backups stay in the bucket — this only forgets how to reach them. Delete them at the provider if that is what you meant, and keep the passphrase until you have.
