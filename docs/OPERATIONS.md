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

| Path                                                                                     | Purpose                                      |
| ---------------------------------------------------------------------------------------- | -------------------------------------------- |
| `/pdrive`                                                                                | Real owner-only FUSE mountpoint              |
| `~/.local/bin/pdrive-*`                                                                  | User-facing helpers                          |
| `~/.local/share/applications/io.github.claudiuschuster.PDriveControl.desktop`            | Cinnamon menu entry                          |
| `~/.local/share/icons/hicolor/scalable/apps/io.github.claudiuschuster.PDriveControl.svg` | Scalable UI icon                             |
| `~/.local/bin/rclone`                                                                    | Adds the Keyring-backed `--password-command` |
| `~/.local/libexec/rclone-bin`                                                            | Signed stable rclone executable              |
| `~/.local/libexec/rclone-proton-*`                                                       | Mount and guarded unmount implementation     |
| `~/.config/rclone/rclone.conf`                                                           | Encrypted rclone configuration               |
| `~/.config/pdrive-*.conf`                                                                | Strict single-purpose helper settings        |
| `~/.cache/rclone`                                                                        | VFS data and metadata cache                  |
| `~/.local/state/rclone`                                                                  | Logs, RC socket and watchdog state           |
| `~/.config/systemd/user`                                                                 | User service and timers                      |

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

### `pdrive-state` and PDrive Control Center

```bash
pdrive-state
pdrive-state --compact
pdrive-ui
pdrive-ui --background
pdrive-ui --check
```

`pdrive-state` is a fast, read-only JSON adapter. It concurrently reads
`core/stats`, `core/transferred`, `core/bwlimit`, `vfs/queue` and `vfs/stats`
as HTTP directly from the existing owner-only RC Unix socket, then combines those live values
with systemd, `findmnt`, strict helper configuration and the latest watchdog
snapshot/history. A partial subsystem failure is represented in
`health.components`; the command still emits a complete schema-versioned JSON
document so local consumers can degrade gracefully. The direct socket transport
avoids launching multiple large rclone CLI processes on every two-second UI
refresh; no TCP listener or additional rclone process is involved.

`pdrive-ui` is the native GTK consumer of that document. While visible, it
refreshes every two seconds in a background thread, keeps a five-minute
in-memory speed graph and
shows active transfer and queue names only in the current desktop process. It
does not modify the privacy-preserving watchdog files, start a second rclone,
read the encrypted remote configuration, open a network listener or contact
Proton independently.

The overview's **Unreviewed issues** card uses persistent watermarks for the
current rclone log's cumulative error and notice counters. It therefore does
not reset at the next 90-minute timer sample. The first 0.3.x start establishes
a zero baseline; pressing the card's checkmark advances that baseline without
deleting logs, watchdog history or current health warnings. Counter resets
caused by log rotation are treated as a fresh log rather than a negative delta.

The Active, Queue and VFS-Cache overview cards provide keyboard and pointer
shortcuts into the corresponding Transfers sections. The cache
section distinguishes pending protected upload data from clean synced copies,
shows running versus saved retention and explains why a non-empty cache can be
healthy while the upload queue is empty.

The control popover calls existing helpers instead of duplicating their
validation:

- bandwidth applies live through `pdrive-bwlimit` without restarting a transfer;
- upload slots are persisted through `pdrive-transfers` for the next start;
- clean-cache retention is persisted through `pdrive-cache-age` for the next
  start and is also configurable in the Transfers cache section;
- cooldown reset delegates to `pdrive-watch --clear-cooldown`;
- metadata refresh and service restart open their existing guarded helpers in a
  terminal, preserving the explicit confirmation and queue checks.

The same popover opens the Preferences dialog and a native Markdown
documentation window with Getting started, Operations and Troubleshooting
pages. It prefers `$XDG_DATA_HOME/doc/proton-drive-linux`, then conventional
`/usr/share/doc/proton-drive-linux` package files and finally a development
checkout. Headings, lists, tables, quotations, code and links are rendered by
GTK without WebKit or another runtime dependency. The popover is constructed
with visible child widgets but remains closed until the user activates its
header button.

`--check` validates GTK and locates `pdrive-state` without opening a window.

The Preferences dialog persists three booleans plus the selected `en`/`de`
interface language in mode-0600 `~/.config/pdrive-ui.json`. English is the hard
default; selecting German takes effect after restarting the Control Center.
The booleans control close into tray, start with the desktop session and whether
two-second live polling continues while hidden. Background polling defaults to
off; the independent 90-minute watchdog continues monitoring either way, and
opening the window always triggers an immediate refresh.
Enabling session startup atomically manages
`~/.config/autostart/io.github.claudiuschuster.PDriveControl.desktop`, marked
with `X-PDrive-Control-Center=true`, whose command is `pdrive-ui --background`.
The application refuses to overwrite a same-named unmarked file and removes
only its own marked autostart file. A manual menu launch remains visible.

The same owner-only preferences file stores the last normal content width and
height. Resize events are debounced before writing; maximized and fullscreen
geometry is ignored. A fresh profile starts at 1120×932 content pixels, showing
the complete Overview without a vertical scrollbar on Cinnamon while remaining
independent of GTK shadow and header-bar dimensions.

On X11 Cinnamon the tray uses GTK StatusIcon so a left click opens/focuses the
Control Center and a right click opens the existing Open, Open `/pdrive`, and
Quit menu. Ayatana AppIndicator remains the compatibility backend on displays
that cannot provide distinct primary/context clicks. Hiding or quitting the UI
never stops the mount; monitoring, recovery and desktop error notifications
remain the responsibility of `pdrive-watch.timer`.

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

## VFS-cache retention

```bash
pdrive-cache-age
pdrive-cache-age 12
pdrive-cache-age 72
pdrive-cache-age default
```

The default is 24 hours, measured since a clean cache file was last accessed.
Valid whole-hour values range from 1 through 8760. The helper writes one
mode-0600 configuration atomically and does not restart the mount. The running
VFS owns a copy of its startup options, so the saved value becomes active at
the next controlled service start. `pdrive-cache-age` and the Control Center
show both values when they differ.

This setting governs eviction of clean, already-synced local data. Dirty files
waiting for upload remain protected even when the age, 25 GiB target or minimum
free-space target is exceeded. The one-minute cache poll means eligible clean
data may remain briefly after its age expires.

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
`RESTART`. It asks systemd for one non-blocking restart, sets the recovery
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

| Signal                              | Protective threshold |
| ----------------------------------- | -------------------: |
| process `read_bytes`                |                1 MiB |
| process `rchar`                     |                8 MiB |
| established rclone TCP `bytes_sent` |              256 KiB |

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
maximum cache age:     24 hours by default; configurable with pdrive-cache-age
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
