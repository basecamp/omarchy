# System Commands and Packages

Use this guide for packages, optional software, updates, system setup, reminders,
and lock, logout, reboot, or shutdown operations.

## Discover the Supported Operation

Start with the narrowest matching group:

```bash
omarchy install --help
omarchy pkg --help
omarchy setup --help
omarchy system --help
omarchy update --help
omarchy reminder --help
```

Read the selected action's help before running it. Interactive setup and install
commands belong in a visible terminal where the user can answer prompts and
authenticate.

## Packages and Optional Software

Choose the highest-level supported interface:

1. Use `omarchy install ...` for software with an Omarchy installer, integration, or setup flow.
2. Use `omarchy pkg add <packages...>` for ordinary repository packages.
3. Use `omarchy pkg aur add <packages...>` for packages that require the AUR.
4. Use `omarchy pkg drop <packages...>` for removal after user confirmation.

Package work is complete when the command exits successfully,
`omarchy pkg present <packages...>` confirms the expected installed state, and
the requested program or service starts when applicable. For removal, run
`omarchy pkg missing <package>` separately for every named package and require
each check to succeed.

## Updates

Run `omarchy update` only for an explicit update request. Keep the command in a
visible terminal because updates may request input, authentication, or a
restart. If it fails, preserve the output and use:

```bash
omarchy update analyze logs
```

An update is complete when the update command succeeds and every requested
restart has either been performed or reported as pending. A failed update is
complete only as a diagnosis when the failing stage and retained logs are
identified.

## Setup

`omarchy setup` actions can change authentication, boot, networking, and other
system-wide behavior. Inspect the action's help, state the affected subsystem,
and follow the core privilege and destructive-operation rules. Exercise the
configured capability after setup rather than treating a successful exit as
sufficient.

Factory reset is destructive recovery, not ordinary setup. It permanently
erases every user account and everything under `/home`; it does not create a
recoverable user-data backup. It also requires the `@factory` snapshot created
by a Quattro ISO installation and rejects upgraded systems without that
snapshot. Follow the reset rules in `SKILL.md` and obtain immediate
confirmation after explaining those constraints.

## Reminders

```bash
omarchy reminder 15 "Pickup Jack"
omarchy reminder show
omarchy reminder show --json
omarchy reminder clear
```

Plain `omarchy reminder show` displays a desktop notification. Reminder work is
complete when `omarchy reminder show --json` reports the requested message and
time. Obtain confirmation before clearing reminders the user did not
individually identify.

## Session and Power

Use `omarchy system lock` directly for a lock request. Logout, reboot, and
shutdown end the user's current work: treat a direct request to perform that
specific action as confirmation; otherwise obtain confirmation immediately
before executing it.

A session or power operation is complete when the requested transition begins.
Report unsaved-work or restart risk before issuing the command when it is
known.
