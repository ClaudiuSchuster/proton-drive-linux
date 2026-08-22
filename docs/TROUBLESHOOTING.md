# Troubleshooting

Start locally. Repeated Proton login tests and blind service restarts can make a
temporary condition worse.

```bash
pdrive-watch
pdrive-doctor
systemctl --user status rclone-proton-drive.service
journalctl --user -u rclone-proton-drive.service -n 100 --no-pager
```

Only add `pdrive-doctor --online` when no HTTP 429 backoff is active and a real
API test is necessary.

## Mount missing after login

Check the exact chain:

```bash
systemctl --user is-enabled rclone-proton-drive.service
systemctl --user show rclone-proton-drive.service \
  -p ActiveState -p SubState -p MainPID -p Result -p ExecMainStatus -p NRestarts
findmnt -M /pdrive
timeout 5 secret-tool lookup service rclone account proton-drive >/dev/null
```

Expected: enabled, active/running, a non-zero PID, `Result=success`, a
`fuse.rclone` mount and a successful Keyring lookup. The service starts after
the graphical login, not at the display-manager screen, because the login
Keyring must be unlocked first.

If `/pdrive` was deleted or has the wrong owner:

```bash
sudo install -d -m 0700 -o "$(id -un)" -g "$(id -gn)" /pdrive
systemctl --user start rclone-proton-drive.service
```

The wrapper refuses symlinks or foreign ownership rather than mounting over an
unexpected path.

## `fusermount3: entry ... not found in /etc/mtab`

This commonly means an unmount was requested when no matching mount existed. It
is not itself proof that FUSE is broken. The shipped unmount helper first checks
`mountpoint` and `findmnt` and only calls `fusermount3` for a confirmed FUSE or
rclone filesystem.

## `Transport endpoint is not connected`

The FUSE process disappeared while the kernel mount entry remained. Confirm no
important queue is recoverable only from the running process, then:

```bash
fusermount3 -uz /pdrive
systemctl --user start rclone-proton-drive.service
```

Do not delete `~/.cache/rclone` as a generic fix. It may hold the only complete
local copy of writes that have not reached Proton.

## Service remains `activating (start)`

This can be valid during a large persisted VFS-cache inventory or while waiting
for the Keyring. Inspect process age, cache, queue and log movement with
`pdrive-watch`. The unit deliberately uses an unlimited start timeout so systemd
does not repeatedly kill a legitimate Proton backoff or a long startup scan.

If no queue exists and the Keyring is locked, log out and back into Cinnamon or
repair the login-Keyring/PAM integration. Do not add automatic password files as
a shortcut.

## No traffic for several minutes

No traffic is normal when:

- the live VFS queue is empty;
- rclone is listing or decrypting many small metadata objects;
- an upload is in bounded API retry/backoff;
- another process still holds a write-open file;
- the bandwidth limit is unexpectedly low.

Check:

```bash
pdrive-watch
pdrive-bwlimit
pdrive-transfers
```

The decisive distinction is not “zero traffic”, but old queued work plus no
meaningful process reads, no sent TCP payload and repeated confirmation. The
watchdog applies that distinction automatically. A 100 GB file can run for many
hours without completing and must not be restarted while bytes still move.

If the queue is genuinely stuck, DNS is healthy, no TCP/read activity is
measurable and the report recommends recovery, use one controlled restart:

```bash
pdrive-watch --restart-service
```

Do not chain repeated restarts. Each one can restart a file upload and rebuild
the persistent queue inventory.

## Wi-Fi or router reconnects

Brief network loss should normally recover through rclone's bounded retries.
The monitor treats DNS failure as network evidence, not as permission for a
restart loop. Stabilize the network first; Ethernet or a lower upload rate can
help overloaded consumer routers:

```bash
pdrive-bwlimit 3
```

Remove the temporary limit later with `pdrive-bwlimit off`. Live changes do not
interrupt the current transfer.

## Bandwidth is only a few KiB/s

Run `pdrive-bwlimit`. rclone's raw numeric bandwidth syntax can be surprising;
this helper deliberately treats every unitless component as MiB/s:

```text
4       -> 4M:off
4.2     -> 4.2M:off
4:1     -> 4M:1M
800K    -> 800K:off
```

The left side is upload and the right side is download. The units are bytes per
second. A stale value can be corrected live without restarting the mount.

## Nemo is slow or shows stale folders

First distinguish the two caches:

1. rclone's one-hour VFS directory cache speeds revisiting folders and tracks
   operations made through this mount;
2. the optional Proton backend metadata cache persists in process memory and
   cannot see changes made by other clients.

Nemo `F5` refreshes its view but cannot empty the deeper backend maps. After an
external Web/mobile/CLI change, run:

```bash
pdrive-refresh --refresh
```

It refuses to restart while any VFS queue, active upload or Dirty data exists.
If external writers are routine, leave the metadata cache disabled:

```bash
pdrive-recovery --disable
pdrive-watch --restart-service
```

## Nemo Extra Pane or breadcrumb mismatch

Use `/pdrive` directly. A Home-directory symlink can be classified by GIO as
the underlying home filesystem rather than the resolved FUSE mount, which can
confuse Nemo's mount-aware second-pane behavior. The root-level mount also lies
outside the locations GVfs normally presents as removable devices, so it avoids
a casual eject icon while remaining a normal FUSE mount.

## File remains Dirty or upload never appears remotely

An application may still hold the file open, the write-back delay may not have
elapsed, or the upload may be retrying. Inspect the local queue:

```bash
pdrive-watch
pdrive-refresh
```

Never remove VFS data or metadata while Dirty files exist. Cache cleanup is
safe only after the queue and Dirty counts are zero and important remote files
have been independently verified.

## HTTP 401 or expired session

Use local diagnostics first. If the stored session truly cannot refresh or the
account password changed:

```bash
pdrive-reauth --reauth
```

The helper backs up the encrypted configuration and makes one bounded login
attempt. It starts the mount only after success.

## HTTP 429, CAPTCHA or too many recent logins

Stop trying. Leave the mount service stopped, wait for Proton's complete stated
backoff plus a few minutes, then make exactly one reauthentication attempt.
Rapid service retries, online doctor calls and repeated password tests can
extend the restriction or trigger additional abuse protection.

The mount unit's one-hour restart delay and unlimited start timeout exist to
avoid such login hammering.

## HTTP 422: draft or name already exists

A normal name conflict and an incomplete server-side upload draft can both
produce 422 responses. Do not immediately enable replacement.

First confirm all of the following:

- the target is an incomplete draft rather than a valid existing file;
- the complete local source is still preserved in the VFS cache or elsewhere;
- no other Proton client is writing;
- the exact VFS backend namespace for the changed options is understood;
- a normal retry or one controlled restart does not resolve it.

Only then consider `pdrive-draft-recovery --enable`. It intentionally does not
restart rclone. `replace_existing_draft` changes remote state and can also alter
the cache namespace selected by backend options. A blind restart can make the
local queue appear to vanish even though its data still exists under another
cache directory. Treat namespace mapping and Remote verification as a manual,
audited recovery procedure.

Disable draft replacement only after every Proton Dirty file is gone. The
helper enforces that final guard.

## HTTP 5xx and storage failures

Proton or its storage layer may transiently return 500, 502 or similar errors.
The mount uses five low-level attempts and two high-level attempts to recover
without endless loops. If aggregate bytes continue to move, leave it alone.

If all upload slots become silent after a 5xx and the watchdog confirms no
process or network payload across repeated checks, one controlled restart is
reasonable. Preserve the cache and do not reauthenticate unless the error is
actually authentication-related.

## One versus four upload slots

Four slots are normal and best for mixed workloads:

```bash
pdrive-transfers default
```

For a tiny remaining queue of exceptionally large files where one failing
parallel block repeatedly cancels all other active requests, serial recovery can
reduce the failure surface:

```bash
pdrive-transfers 1
pdrive-watch --restart-service
```

Return to four after recovery. Changing the configuration alone never restarts
the service.

## Disk space and cache cleanup

The mount targets a 25 GiB cache and preserves at least 50 GiB free space, but
Dirty upload data cannot safely be evicted merely to satisfy a cache target.
Check:

```bash
du -sh ~/.cache/rclone
df -h "$HOME"
pdrive-refresh
```

Old clean backend namespaces can exist after changing Proton backend options.
Before removing one, prove it is not selected by the running process, contains
zero Dirty metadata, is absent from the live queue and is not the only local
copy of a file. When uncertain, keep it.

## Useful logs and state

```text
~/.local/state/rclone/proton-mount.log
~/.local/state/rclone/proton-mount.log.*
~/.local/state/rclone/proton-reauth.log
~/.local/state/rclone/pdrive-watch-latest.txt
~/.local/state/rclone/pdrive-watch-history.log
~/.local/state/rclone/pdrive-watch-state
```

The mount log rotates at 10 MiB, retains three compressed backups and expires
old rotations after 30 days. Logs can contain personal file paths. Redact them
before posting a bug report.

## Reporting an issue

Include:

- distribution, desktop and rclone version;
- output of `pdrive-doctor` with personal paths redacted if needed;
- output of `pdrive-watch`;
- relevant journal and mount-log excerpts, not the complete private log;
- whether Web/mobile/CLI clients changed data concurrently;
- whether the queue or Dirty count was non-zero before a restart.

Never include `rclone.conf`, Keyring exports, Proton passwords, 2FA codes,
session tokens or complete private filenames unless they are essential and have
been safely anonymized.
