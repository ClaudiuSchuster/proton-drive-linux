# Operations handbook

This document describes the installed runtime, safe daily operation and every
helper command. Command output is currently German because the deployment from
which the toolkit was extracted is German-language Linux Mint.

## Runtime architecture

```text
Cinnamon login
  -> login-unlocked GNOME Keyring
  -> user systemd
  -> rclone-proton-drive.service
  -> ~/.local/libexec/rclone-proton-mount
  -> ~/.local/bin/rclone (Keyring password wrapper)
  -> ~/.local/libexec/rclone-bin
  -> /pdrive (FUSE)
```

The mount service waits for the Keyring item instead of repeatedly attempting
Proton logins before the desktop session has unlocked it. Its start timeout is
unlimited so a legitimate Proton backoff is not killed after systemd's usual
90 seconds. Failed service starts are delayed by one hour.

## Installed files

| Path | Purpose |
| --- | --- |
| `/pdrive` | Real owner-only FUSE mountpoint |
| `~/.local/bin/pdrive-*` | User-facing helpers |
| `~/.local/bin/rclone` | Adds the Keyring-backed `--password-command` |
| `~/.local/libexec/rclone-bin` | Signed stable rclone executable |
| `~/.local/libexec/rclone-proton-*` | Mount and guarded unmount implementation |
| `~/.config/rclone/rclone.conf` | Encrypted rclone configuration |
| `~/.config/pdrive-*.conf` | Strict single-purpose helper settings |
| `~/.cache/rclone` | VFS data and metadata cache |
| `~/.local/state/rclone` | Logs, RC socket and watchdog state |
| `~/.config/systemd/user` | User service and timers |

The configuration files are parsed as data and are never sourced as shell code.
Each helper accepts only one narrowly validated key/value form.
The RC API socket is owner-only mode `0700` (`srwx------`) under the service's
`UMask=0077`; it is never exported to a TCP listener.

## First setup

`pdrive-setup` without options and `pdrive-setup --help` only print guidance.
The explicit setup is:

```bash
pdrive-setup --setup
```

It refuses an existing `~/.config/rclone/rclone.conf`, a foreign or symlinked
`/pdrive`, missing dependencies and non-interactive terminals. The Proton
password is obscured by rclone and the complete configuration is then encrypted
with a random secret stored under the Keyring attributes:

```text
service=rclone
account=proton-drive
```

The one-time 2FA code is cleared immediately after the bounded initial login,
whether that login succeeds or fails.

## Status and diagnosis

### `pdrive-doctor`

```bash
pdrive-doctor
pdrive-doctor --online
pdrive-doctor --help
```

The default run is local. It reads OS and rclone versions, service and mount
state, Keyring availability, a redacted configuration summary, required Debian
packages, timers, storage, journal messages and the rotated mount log. It does
not log in or call Proton.

`--online` adds exactly one directory listing bounded to 60 seconds with one
high-level attempt and no low-level retries. Never use it while a Proton HTTP
429 wait is active.

### `pdrive-watch`

```bash
pdrive-watch
pdrive-watch --help
```

The default run produces a fresh report without advancing the timer comparison
point. It summarizes:

- service state, PID, age, restart count, CPU and resident memory;
- FUSE mount, DNS and active TCP state;
- upload successes, queued events, errors and notices in the current log;
- live VFS queue count, bytes, active uploads and retry candidates;
- metadata-cache mode, transfer slots, cache size and free disk space;
- automatic-recovery cooldown and a contextual recommendation.

The timer alone calls `pdrive-watch --record`. That mode atomically updates
owner-only state files and sends desktop notifications on important changes.
Do not use `--record` as an interactive status shortcut.

### Reading counters correctly

The `Uploads`, `queued`, `errors` and `notices` totals come from lines in the
current uncompressed `proton-mount.log`. They are not counts of unique files and
they do not mean that every historical error is still open. One failed Proton
block request can produce an attempt notice, the HTTP error, several cancelled
parallel requests, a `Failed to copy` summary and a later VFS retry line.

Use the deltas since the previous timer run to understand recent change, and use
the live `VFS-Queue` plus Dirty count to decide what is actually pending now. A
manual `pdrive-watch` call intentionally does not advance that timer baseline.
Log rotation resets or lowers line totals; the report labels that as a new log
rather than presenting a negative delta.

## Runtime bandwidth

```bash
pdrive-bwlimit
pdrive-bwlimit 4.2
pdrive-bwlimit 4:1
pdrive-bwlimit 800K
pdrive-bwlimit off
```

A single value means upload limit with unlimited download. A colon separates
upload and download. Every unitless numeric component receives the rclone `M`
suffix before validation, so `4:1` becomes `4M:1M`. Values are bytes per second,
not bits per second.

The helper first asks rclone's loopback parser to canonicalize the value, writes
one mode-0600 config atomically, then updates the live process through the
owner-only Unix socket. A live transfer is not restarted.

## Transfer concurrency

```bash
pdrive-transfers
pdrive-transfers 1
pdrive-transfers default
```

Values from 1 through 8 are accepted. Four is the normal default. This is a
process-start setting, so changes are saved but do not restart rclone. One slot
is useful only for exceptional large-file recovery where parallel Proton block
requests repeatedly fail together.

## Metadata-cache mode

```bash
pdrive-recovery
pdrive-recovery --enable
pdrive-recovery --disable
```

Despite its historical name, this helper selects the normal Proton backend
metadata behavior:

- disabled: safe when Web, mobile, official CLI or other clients make changes;
- enabled: much faster navigation when this rclone process is the exclusive
  writer, but external changes remain invisible in its process-local cache.

Both switches affect only the next service instance. Disabling is refused while
any Proton VFS metadata file is Dirty, because backend options contribute to
rclone's VFS cache namespace.

## Refresh after external changes

```bash
pdrive-refresh
pdrive-refresh --refresh
```

The default is action-free status. `--refresh` is the safe complete refresh:

1. verify the service is active;
2. read the live VFS queue through the Unix socket;
3. scan all Proton VFS metadata for Dirty files;
4. refuse if any queue, upload or Dirty item exists;
5. delegate to the confirmed `pdrive-watch --restart-service` path.

rclone's `vfs/forget` only clears the upper directory cache. A new process is
required to guarantee that the Proton backend's deeper in-memory metadata maps
are empty.

## Controlled restart and cooldown

```bash
pdrive-watch --restart-service
pdrive-watch --set-cooldown 6h
pdrive-watch --set-cooldown default
pdrive-watch --clear-cooldown
```

The restart command requires an interactive terminal and the exact word
`NEUSTART`. It asks systemd for one non-blocking restart, sets the recovery
cooldown and waits up to 60 seconds for a different living PID. It then reports
DNS, mount visibility, log movement and post-request upload successes.

The automatic cooldown defaults to 12 hours and accepts values from one hour to
seven days. Clearing it does not restart rclone or alter the timer baseline.

An empty queue and no traffic is a healthy idle state. Automatic recovery is
considered only after repeated evidence of an old queued upload with no useful
process reads or TCP payload. A currently moving large file therefore does not
trigger a restart merely because it has not completed for many hours.

## Exact watchdog safety gates

The health timer has two deliberately separate detectors.

### Persistent individual upload failure

An individual queue object becomes a warning candidate only after at least two
upload attempts. The same object must remain in two recorded timer observations,
normally 90 minutes apart. Its identity is stored only as a SHA-256 digest of
path and size; the clear path never enters watchdog history or notifications.

If rclone says the candidate is currently uploading, the second observation
measures payload for 20 seconds. Any of these deltas proves useful activity and
resets the confirmation:

| Signal | Protective threshold |
| --- | ---: |
| process `read_bytes` | 1 MiB |
| process `rchar` | 8 MiB |
| established rclone TCP `bytes_sent` | 256 KiB |

A repeatedly waiting object, or an active object again showing no payload,
causes `persistent-upload-failure` and a critical desktop notification. This
detector never restarts rclone and never removes the queue or cache. If the
local RC queue cannot be inspected, the monitor reports
`queue-monitor-unavailable` instead of guessing.

### Startup inventory stall

Automatic recovery is considered only when all of these facts are true:

1. a compatible previous timer baseline exists;
2. the service is still `activating` with a living PID;
3. `/pdrive` is not mounted yet;
4. DNS for Proton Drive is healthy;
5. the last successful upload is at least four hours old;
6. a queue event occurred within the last two hours;
7. the previous comparison is at least one hour old;
8. no upload success was added, while the number of queued log events grew;
9. the 20-second probe stays below all three payload thresholds above; and
10. the same complete finding is recorded twice.

Even then, the timer does not restart when the Proton metadata cache is enabled:
preserving its warm process-local state is a hard blocker. A configured cooldown
also blocks another automatic restart. A ready mount is never interrupted by
this automatic path. DNS failure, low disk space, an invalid helper setting or a
down service produces diagnosis and notification only.

Only `--record` may perform automatic recovery. After the second independent
confirmation it requests one non-blocking systemd restart, retains the VFS
cache, resets the confirmation counter and starts the configured cooldown
(12 hours by default). A manual status call shows what a timer would decide but
never changes the baseline or service.

## Emergency reauthentication

```bash
pdrive-reauth
pdrive-reauth --reauth
```

The no-option form is help only. Use `--reauth` exclusively for an expired or
invalid session, a changed Proton password, or a diagnosis that clearly points
to authentication.

The helper requires `JA`, reads password and optional TOTP silently, then stops
the mount. It backs up the encrypted configuration, clears old client session
fields, performs exactly one bounded login and removes the one-time TOTP. The
mount is restarted only when login succeeds.

After HTTP 429, leave the service stopped and wait for Proton's complete stated
backoff plus a small margin. Repeated “tests” can extend the block.

## Advanced draft recovery

```bash
pdrive-draft-recovery
pdrive-draft-recovery --enable
pdrive-draft-recovery --disable
```

This is not a routine repair switch. Enabling `replace_existing_draft` permits
rclone to delete or replace an incomplete server-side upload draft at the same
target name. The helper requires metadata-cache recovery mode first and does not
restart the service, because the changed backend options may select a different
VFS namespace.

Never enable it without separately verifying where the complete local Dirty
data lives. Disabling is refused until all Proton Dirty metadata is gone. Read
the draft section in [Troubleshooting](TROUBLESHOOTING.md) before use.

## Service control

```bash
systemctl --user status rclone-proton-drive.service
systemctl --user restart rclone-proton-drive.service
systemctl --user list-timers --all
journalctl --user -u rclone-proton-drive.service -n 100 --no-pager
```

Prefer `pdrive-watch --restart-service` over a raw restart because it confirms
intent, records a cooldown and validates the new process. Never restart merely
to make a currently active large upload “look faster”.

## Update schedule and integrity

Inspect all schedules with:

```bash
systemctl --user list-timers --all | grep -E 'rclone|proton-drive|pdrive'
systemctl --user status rclone-selfupdate.timer proton-drive-update.timer
```

The rclone timer runs ten minutes after boot when due and every Sunday at 04:00,
with up to two hours of randomized delay. `Persistent=true` catches up after the
computer was off. rclone's own `selfupdate --stable` verifies the release hash
and cryptographic signature. A newly installed binary is intentionally left for
the next natural mount start; the updater never restarts an active transfer.

The optional official Proton Drive CLI timer runs five minutes after boot when
due and daily with up to four hours of randomized delay. Its updater accepts
only the parsed official `proton.me` x86-64 version URL, downloads over TLS and
atomically replaces the binary only after the release page's SHA-512 value
matches. This CLI is separate from the rclone FUSE mount.

Manual checks:

```bash
systemctl --user start rclone-selfupdate.service
systemctl --user start proton-drive-update.service
journalctl --user -u rclone-selfupdate.service -n 50 --no-pager
journalctl --user -u proton-drive-update.service -n 50 --no-pager
```

After an rclone version change, run `pdrive-doctor`, read a directory and upload
a small disposable test file before performing important moves. Backend beta
behavior can change between rclone releases.

## Normal mount settings

The mount wrapper currently uses:

```text
VFS cache mode:        full
maximum cache size:    25 GiB
minimum free space:    50 GiB
maximum cache age:     168 hours
write-back:            5 seconds
directory cache:       1 hour
attribute cache:       1 second
parallel transfers:    4 by default
low-level retries:     5
high-level retries:    2
permissions:           umask 077
```

The cache limit is not a quota for Dirty data that has not safely uploaded;
rclone must preserve such data. Monitor both cache size and free filesystem
space during large queues.

## Backup and restoration

A normal desktop shutdown lets systemd call the guarded unmount helper. Still,
before planned maintenance verify zero queue and zero Dirty data:

```bash
pdrive-watch
pdrive-refresh
```

Back up at least:

- the encrypted `~/.config/rclone/rclone.conf`;
- helper configuration under `~/.config/pdrive-*.conf`;
- the relevant Keyring secret through an appropriately protected desktop backup;
- the repository or installed scripts and units.

The encrypted configuration is useless without its Keyring password. Never
store an exported cleartext Keyring secret in Git, chat, an unencrypted cloud or
inside the Proton Drive mount itself.

Treat the encrypted configuration and its exact Keyring item as one backup
pair. Copying only `rclone.conf` to another installation does not make it
decryptable. Conversely, a Keyring export is as sensitive as the Proton account
credentials and needs strong independent encryption.

After restoring repository files, the encrypted config and the matching
Keyring item, repair ownership and activation with:

```bash
chmod 600 ~/.config/rclone/rclone.conf
find ~/.config -maxdepth 1 -type f -name 'pdrive-*.conf' -exec chmod 600 {} +
chmod 755 ~/.local/bin/rclone ~/.local/bin/pdrive-*
chmod 755 ~/.local/libexec/rclone-bin ~/.local/libexec/rclone-proton-*
sudo install -d -m 0700 -o "$(id -un)" -g "$(id -gn)" /pdrive
systemctl --user daemon-reload
systemctl --user enable rclone-proton-drive.service \
  pdrive-watch.timer rclone-selfupdate.timer
pdrive-doctor
```

Do not start the service until `pdrive-doctor` can unlock the configuration and
the cache/Dirty state is understood. A restored VFS cache can contain the only
complete copy of pending writes; never merge, rename or delete cache namespaces
blindly. If the Keyring password is unavailable, restore both parts from the
same backup or create a fresh encrypted configuration with `pdrive-setup`; the
old encrypted file cannot be recovered from its ciphertext alone.
