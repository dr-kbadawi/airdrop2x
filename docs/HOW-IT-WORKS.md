# How AirDrop2X works, and how that was established

Everything below was verified on macOS 26.6.2 (build 25G83) in September 2026 by reading the
binaries and sandbox profiles on disk and by watching real transfers in the unified log. The
commands are given so that the findings can be reproduced.

## 1. Where AirDrop writes, and why there is no setting

Files received by AirDrop are written by the system daemon `/usr/libexec/sharingd`. Its
preference domain (`defaults read com.apple.sharingd`) contains no destination key, and its sandbox
profile lists which preference domains it may read; none is a place a folder path could live.

The destination is derived at run time by a function in the private Sharing framework,
`SFAirDropDownloadsURL`, which both sharingd and its helper import. Disassembled (load the framework
in a scratch process and run `disassemble -n SFAirDropDownloadsURL` in lldb), the function is:

```
[NSFileManager URLForDirectory:15 inDomain:1 appropriateForURL:nil create:YES]
    15 = NSDownloadsDirectory, 1 = NSUserDomainMask
on failure: log "Fallback to using the Desktop directory", try NSDesktopDirectory (12)
on failure: log "Fallback to using user's home directory", use NSHomeDirectory()
```

It never reads a preference. The answer is always `$HOME/Downloads`.

## 2. Symlinks are resolved before writing

sharingd does not write through the `~/Downloads` path directly. When a transfer starts it asks an
XPC helper, `SharingXPCHelper` (in `SharingXPCServices.framework`), for a security-scoped URL of the
Downloads folder. The helper's `main` function, read from its disassembly, does:

```
SFAirDropDownloadsURL()                       -> ~/Downloads
SFRealpathForFileURL(url)                     -> realpath(3) of it, symlinks resolved
SFEnterSandbox("com.apple.SharingXPCHelper", "SharingXPCHelper", realpath, 0)
```

`SFEnterSandbox` logs `(Sandbox) Whitelisted Downloads directory is %s` and passes the resolved path
to `sandbox_init_with_parameters` under the parameter name `_DOWNLOADS`. The helper's profile,
`/System/Library/Sandbox/Profiles/com.apple.SharingXPCHelper.sb`, allows it to issue file
extensions only under `(subpath (param "_DOWNLOADS"))`. On request it calls
`sandbox_extension_issue_file(APP_SANDBOX_READ_WRITE, path, 0)` on that real path and returns the
extension wrapped in an `NSSecurityScopedURLWrapper`; sharingd consumes it and writes.

Consequence: if `~/Downloads` is a symbolic link to a folder elsewhere, the helper resolves it and
grants sharingd write access to the folder the link points to. That is the single lever AirDrop2X
uses. Apple's own profile for sharingd (`com.apple.sharingd.sb`) even anticipates the case: it
allows temporary directories "on the volume where the user's Downloads directory is located"
(`(mount-relative-regex #"^/\.TemporaryItems(/|$)")`), which is where incoming files are staged
before being renamed into place.

The helper resolves the path once, at its own launch, and is started on demand. AirDrop2X ends a
running helper after every switch so the next transfer resolves the current path.

## 3. Why the real Downloads folder is renamed

Only one thing can sit at the path `~/Downloads`. To make the path resolve elsewhere it has to be a
symlink, so the real folder is renamed to `~/Downloads.local` for as long as the switch is on. A
rename on the same volume is a single metadata change; the contents are untouched. Switching off
is the reverse rename.

macOS puts the access control entry `group:everyone deny delete` on the standard home folders. A
rename needs delete permission on the entry being renamed, so with that ACE in place `rename(2)`
fails with `EACCES`. AirDrop2X lifts the entry just before parking and puts it back when Downloads
is restored (`chmod -a` / `chmod +a "group:everyone deny delete"`).

## 4. Why sharingd needs Full Disk Access for a destination on another volume

With the redirect in place, a transfer to a folder on an external NTFS disk went to `/private/tmp`
instead. The unified log (`log show --predicate 'process == "sharingd" OR process == "SharingXPCHelper"'`)
showed:

```
SharingXPCHelper: (Sandbox) Whitelisted Downloads directory is <private>
SharingXPCHelper: issuing sandbox extension failed for url: <private>
sharingd:         Failed to accees downloads directory, falling back
```

and the kernel:

```
System Policy: SharingXPCHelper(pid) deny(1) file-issue-extension
    target:/Volumes/<disk>/<folder> extension-class:com.apple.app-sandbox.read-write
```

"System Policy" denials come from the privacy layer (TCC), not from the sandbox profile. tccd's log
shows the checks it ran, attributed to the *responsible process* `/usr/libexec/sharingd`:
`kTCCServiceSystemPolicyAllFiles` (Full Disk Access) and then
`kTCCServiceSystemPolicyRemovableVolumes`. sharingd's entitlements
(`codesign -d --entitlements :- /usr/libexec/sharingd`) grant it Contacts, Photos and one internal
service, not removable volumes, and a daemon cannot show a permission prompt, so the answer is a
silent no. The same `sandbox_extension_issue_file` call succeeds from a terminal that already holds
Full Disk Access, which rules out the file system as the cause.

The "Removable Volumes" list in System Settings cannot be edited by hand, but Full Disk Access can,
and it covers removable and network volumes. Adding `/usr/libexec/sharingd` there resolves it; tccd
identified sharingd by path (`subject=/usr/libexec/sharingd`), which is why adding it by path
matches. No application can grant that permission on another program's behalf: the privacy
database is protected by System Integrity Protection, configuration profiles for it require MDM
enrollment, and there is no API. This is the one step the user has to perform.

Whether sharingd has the grant cannot be read by an ordinary app either (the database is readable
only with Full Disk Access, and querying tccd about another process needs a private entitlement),
which is why AirDrop2X verifies the setup by watching a real transfer land, and why it keeps
watching `/private/tmp` for AirDrop-tagged files (quarantine attribute `...;sharingd;...`) while the
redirect is on, moving any that fall back there.

## 5. What cannot be done

- sharingd cannot be modified, replaced or injected into: it lives on the sealed system volume, is
  a platform binary with a hardened runtime, and its launchd registration is protected.
- Its XPC interface requires Apple-private entitlements and has no "write here" request; a helper
  started by a third-party app is attributed to that app, so it would test the wrong permissions.
- A Mac cannot AirDrop to itself, so the setup test needs a second device.
