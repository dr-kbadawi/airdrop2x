# AirDrop2X

A macOS menu bar app that makes AirDrop deliver files straight into a folder of your choosing,
on any disk or volume, instead of `~/Downloads`. Switch it on, AirDrop lands in your folder.
Switch it off, Downloads is back to normal.

## How it works

macOS has no setting for the AirDrop destination. `sharingd` (the system daemon behind AirDrop)
asks Foundation for the user's Downloads directory, always `$HOME/Downloads`, resolves symlinks on
it with `realpath()`, and its helper grants write access to the resolved path. Apple's own sandbox
profile allows for the Downloads folder living on another volume.

So AirDrop2X does the one thing that lever permits:

- **On**: the real `~/Downloads` is renamed to `~/Downloads.local` (instant, nothing is copied),
  and `~/Downloads` becomes a symlink to your destination. AirDrop now writes there directly.
- **Off**: the symlink is removed and `~/Downloads.local` is renamed back.

While the app runs it also keeps the state consistent: if the destination becomes unreachable
(disk unplugged, network share gone, folder renamed), the real Downloads is restored so nothing
dangles, and the redirect is re-applied when the destination is back. Quitting the app restores
Downloads too; the switch position is remembered and re-applied at the next launch.

Safety rules: the destination is never created, nothing is deleted except the symlink the app
made, and the app refuses to act if both a real `~/Downloads` and `~/Downloads.local` exist.

## Build

```bash
./build-app.sh
```

Produces `dist/AirDrop2X.app` (menu bar app) and `dist/airdrop2x` (command-line companion).
Copy the app to `/Applications` and open it. It shows the AirDrop2X glyph in the menu bar.

```bash
./make-dmg.sh
```

Produces `dist/AirDrop2X-<version>.dmg`, a drag-and-drop installer with an Applications shortcut.
Local builds are ad-hoc signed, so on first launch right-click the app and choose Open.

```bash
./release.sh
```

Release pipeline: signs the app with the Developer ID certificate (hardened runtime, secure
timestamp), submits it for notarization, staples the ticket, builds the disk image from the stapled
app, notarizes and staples that too, and verifies both with Gatekeeper. The notarization
credentials must be stored once in the keychain with `xcrun notarytool store-credentials`; the
profile name is the `NOTARY_PROFILE` variable. Ready-made, notarized images are attached to the
[releases](https://github.com/dr-kbadawi/airdrop2x/releases).

## Use

1. Menu bar icon → **Choose Destination…** → pick any existing folder (internal disk, external
   drive, network share, disk image).
2. Tick **Redirect AirDrop**. The icon fills in and the menu shows where AirDrop lands.
3. Untick it when done. Downloads is normal again.
4. Optional: **Start at Login**.

While the redirect is on, the app asks every 5 minutes whether to keep it on ("Yes, keep it on" /
"Done, switch it off"), so it does not stay on by accident. The interval is the `reminderMinutes`
setting in the config file; 0 disables the reminder.

On first use macOS asks the app for permission to access the Downloads folder. Allow it.

### First-time setup (required once)

Files received by AirDrop are written by the macOS system process `sharingd`. macOS only lets it
write into the Downloads folder on the internal disk; writing anywhere else needs Full Disk Access,
and only the user can grant that, in System Settings. The first time you switch the redirect on, the
app opens a guide:

1. "Open Full Disk Access" opens System Settings on the right page and copies
   `/usr/libexec/sharingd` to the clipboard.
2. Click "+", press ⌘⇧G, paste, Return, Open. Make sure the new "sharingd" entry is switched on.
3. Click "I've added it — test now" and AirDrop any file to the Mac.

If the file lands in the destination, setup is complete and never asked again. If macOS still
blocks sharingd, it writes the file to `/private/tmp` instead; the app notices, moves the file to
your destination, and reopens the guide with the reason from the system log. This rescue also runs
permanently while the redirect is on, so no transfer is lost if the permission is ever reset.

## Command line

```
airdrop2x destination <folder>
airdrop2x on
airdrop2x off
airdrop2x status
airdrop2x config
```

The CLI shares the app's settings file (`~/Library/Application Support/airdrop2x/config.json`).
Without the app running, `on` and `off` act once and immediately, with no watching.

## Notes

- Finder's sidebar and the Dock's Downloads stack track the folder by identity, so while the
  redirect is on they may keep showing the parked local folder. This reverts on switch off.
- `SharingXPCHelper` caches the resolved Downloads path for its lifetime. The app ends it after
  each switch so the next transfer uses the new path.
- Set `AIRDROP2X_CONFIG_DIR` to use a separate settings directory (used for testing).

## Development and tests

```bash
make test        # all suites
make coverage    # per-file line coverage
```

Three test targets, all runnable with plain `swift test` (no Xcode project needed):

- **AirDrop2xCoreTests**: unit tests for settings, destination checks, file inspection, the
  protective ACL handling, every transition of the redirect state machine (including crash
  leftovers and the ACL round trip), the arrival watcher and rescue, and the daemon's
  reconciliation (switch on/off, destination vanishing and returning, launch rule, fallback
  rescue, setup verification). Each test runs in its own temporary tree with a fake home folder;
  notifications and the sharing-helper reset are captured instead of executed.
- **AirDrop2xAppTests**: the menu model for every state, the drawn menu bar glyph (size, color,
  ring separation), the switch rows, dialog icon centering, and the setup window's states.
- **airdrop2xCLITests**: end-to-end runs of the built `airdrop2x` binary against an isolated
  settings directory.

Continuous integration (`.github/workflows/ci.yml`) builds, runs all tests with coverage, and
packages an ad-hoc signed disk image as an artifact on every push and pull request.

## License

Copyright © 2026 Dr. Karim Badawi, Techtag GmbH.

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. See [LICENSE](LICENSE) for the full text.
