# Operations handbook

This document describes the installed runtime, safe daily operation and every
helper command. Public documentation and the default graphical interface use
English; terminal helpers and diagnostics are English-first. The GUI
additionally provides a complete German translation, and desktop notifications
follow its saved language preference when available.

## Runtime architecture

```text
Cinnamon login
  -> login-unlocked GNOME Keyring
  -> user systemd
  -> rclone-proton-drive.service
  -> pdrive-service (fixed action dispatcher)
  -> project libexec/rclone-proton-mount
  -> project bin/rclone (Keyring password wrapper)
  -> ~/.local/libexec/rclone-bin
  -> /pdrive (FUSE)
```

The mount service waits for the Keyring item instead of repeatedly attempting
Proton logins before the desktop session has unlocked it. Its start timeout is
unlimited so a legitimate Proton backoff is not killed after systemd's usual
90 seconds. Transient failed service starts are delayed by one hour. A terminal
Proton 2FA requirement is different: the authentication guard cancels the
scheduled retry after the first failure, records a credential-free state and
sends one desktop notification so repeated login sessions cannot accumulate.
Before any later service start, a systemd `ExecCondition` permits only an absent
legacy state or a fully validated `ready` state. A terminal or malformed state
therefore skips rclone without contacting Proton or scheduling another retry;
the transactional reauthorization path writes `ready` only after its isolated
candidate login succeeds.

## Installed files

The copy-based installer keeps immutable application files under `~/.local`.
Native distribution packages install the same source tree under
`/usr/lib/proton-drive-linux`, expose public commands through `/usr/bin`, and
place user units and desktop data in the standard `/usr` locations. In both
layouts, credentials, configuration, state, every VFS cache namespace and the
checksum-pinned mutable rclone build remain per-user and are never owned by the
distribution package.

| Path                                                        | Purpose                                    |
| ----------------------------------------------------------- | ------------------------------------------ |
| `/pdrive`                                                   | Real owner-only FUSE mountpoint            |
| `~/.local/bin` or `/usr/bin`                                | User-facing commands                       |
| `~/.local/libexec` or `/usr/lib/proton-drive-linux/libexec` | Immutable internal helpers                 |
| `~/.local/share/applications` or `/usr/share/applications`  | Desktop menu entry                         |
| `~/.config/systemd/user` or `/usr/lib/systemd/user`         | User service and timers                    |
| `~/.local/libexec/rclone-bin`                               | Checksum-verified PDrive rclone executable |
| `~/.config/rclone/rclone.conf`                              | Encrypted rclone configuration             |
| `~/.config/pdrive-*.conf`                                   | Strict single-purpose helper settings      |
| `~/.cache/rclone`                                           | VFS data and metadata cache                |
| `~/.local/state/rclone`                                     | Logs, RC socket and watchdog state         |

The configuration files are parsed as data and are never sourced as shell code.
Each helper accepts only one narrowly validated key/value form.
The RC API socket is owner-only mode `0700` (`srwx------`) under the service's
`UMask=0077`; it is never exported to a TCP listener.

## First setup

When `~/.config/rclone/rclone.conf` is absent, PDrive Control Center opens its
integrated first-run wizard. Its readiness page checks required commands, the
owner-only `/pdrive` directory and the user-local rclone Proton backend. On
Debian-family systems and Arch Linux it can use Polkit to run the fixed system
executables `/usr/bin/apt-get` or `/usr/bin/pacman`, followed separately by
`/usr/bin/install` for the mountpoint; project scripts always remain
unprivileged. An expandable section provides equivalent manual commands for
advanced users. `pdrive-platform` owns the exact distribution match and package
map and never performs an installation itself.

The next page configures connection headroom before Proton authentication:

- **Auto-tune (recommended)** downloads and uploads bounded Cloudflare test
  payloads totaling about 72 MB, chooses conservative samples and assigns 60%
  to bulk PDrive file data. The remaining 40% is left to Nemo metadata,
  interactive traffic and other applications.
- **Set manually** exposes separate logarithmic Upload and Download sliders.
  Use measured sustained throughput rather than an ISP's headline bit rate;
  leaving roughly 30–40% unused normally keeps the desktop responsive.
- **Unlimited** removes both file-data limits. It maximizes throughput but a
  saturated connection can still affect unrelated applications.

The selected pair is saved atomically and applied live when a mount already
exists. Limits affect Proton file payloads only; login, directory listing and
other backend metadata stay outside them. The test result is stored locally in
mode-0600 JSON and contains rates and timestamps, never credentials.

The account page transports username, password and the optional current 2FA
code as three NUL-delimited values over an anonymous stdin pipe. They never
appear in process arguments, environment variables or logs, and the password
and 2FA widgets are cleared as soon as the bounded worker starts.

`pdrive-setup` without options and `pdrive-setup --help` remain action-free.
The equivalent explicit terminal setup is:

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

The login test uses a temporary mode-0600 encrypted configuration. The final
`rclone.conf` is installed atomically only after that one bounded test succeeds;
failed logins leave no final or temporary config. The one-time 2FA code is
cleared immediately after the test, whether it succeeds or fails. Service start
is requested with `systemctl --user start --no-block`, so a slow initial mount
does not freeze the wizard.

### `pdrive-prerequisites`

```bash
pdrive-prerequisites --check
pdrive-prerequisites --install-rclone
pdrive-prerequisites --help
```

`--check` requires both the upload-safe 1.76 baseline and PDrive's Proton
`data-bandwidth` backend command. `--install-rclone` downloads the pinned x86-64
Linux asset from the OSS Singularity rclone release, verifies its published
SHA-256 checksum, version and backend feature in a private temporary file, and
only then atomically installs it as `~/.local/libexec/rclone-bin`. It never
installs system packages or edits `/pdrive` itself; those privileged operations
remain visible Polkit steps in the wizard. Reinstalling the expected asset is a
safe repair when the executable was replaced by an incompatible rclone build.

## Status and diagnosis

### `pdrive-desktop-gate`

```bash
pdrive-desktop-gate --markdown
pdrive-desktop-gate --json
pdrive-desktop-gate --configured --markdown --strict
pdrive-desktop-gate --help
```

The preflight modes collect a versioned, privacy-safe report from the current
graphical login. They check the distribution package map, X11 or Wayland
session, session bus, systemd user manager, GTK/tray stack, FUSE device,
installed desktop assets, core user units, owner-only `/pdrive` directory and
the Control Center self-check. `--configured` additionally reads only local
configuration, keyring availability, service, mount and `pdrive-state`
evidence. It never calls Proton, restarts a service or writes into the mount.

Without `--strict`, the report is always printed and its gate result is encoded
inside it. `--strict` also returns a failing process status when a required
automated check does not pass, which makes tester handoff and release review
unambiguous. No option persists state. No argument and `--help` are action-free.
The remaining visual, tray, file-manager and login checks are listed in
[Real desktop release gates](DESKTOP_GATES.md).

### `pdrive-doctor`

```bash
pdrive-doctor
pdrive-doctor --online
pdrive-doctor --help
```

The default run is local. It reads OS and rclone versions, service and mount
state, Keyring availability, a redacted configuration summary, required
distribution packages, timers, storage, journal messages and the rotated mount
log. It does not log in or call Proton.

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

Notification delivery follows `notification_policy` in the owner-only Control
Center preferences file. **Important** is the default: warning and critical
states plus an issued guarded recovery are announced, while routine ready
transitions stay quiet. **Critical only** reports only critical states, **All**
also reports ready transitions, and **Off** suppresses desktop notifications.
The policy changes delivery only; detection, history and recovery safety gates
continue unchanged. Notifications default to English and follow the saved
English or German Control Center language. Terminal reports remain English so
commands, diagnostics and support instructions stay consistent.

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
avoids launching multiple large rclone CLI processes on every live UI refresh;
no TCP listener or additional rclone process is involved.

`pdrive-ui` is the native GTK consumer of that document. While visible, it
refreshes at the Preferences interval (two seconds by default) in a background
thread, keeps a rolling in-memory speed graph and
shows active transfer and queue names only in the current desktop process. It
does not modify the privacy-preserving watchdog files, start a second rclone,
read the encrypted remote configuration, open a network listener or contact
Proton independently.

The **Recently completed** list is a rolling 24-hour view. `pdrive-state`
combines the current rclone process's `core/transferred` records with successful
VFS uploads reconstructed read-only from the bounded tail of the existing
owner-only mount log. Matching records are shown once, so a normal service or
system restart does not erase a recent successful upload. PDrive compares
rclone's source and destination filesystems with the mounted Proton remote,
exports only the privacy-safe direction `upload`, `download` or `unknown`, and
shows direction separately from the completed/failed result. Persistent log
evidence is upload-only; downloads remain visible while the current rclone
process retains them because the mount log has no equally strong durable
download-completion record. The VFS queue is different: it is the protected
local write-back queue and therefore contains uploads only.

The overview's **Unreviewed issues** card uses a persistent review timestamp;
it therefore does not reset at the next 90-minute timer sample. Adjacent rclone
lines for one backend attempt are correlated, and repeated attempts for the
same affected path become one incident. Runtime evidence then assigns an
explicit lifecycle:

- **active** means no recovery evidence exists;
- **recovering** means the affected item is still queued and retrying; and
- **resolved** requires positive evidence such as a later successful transfer
  of the same path, restored DNS health, or a healthy authenticated mount and
  local control channel after a rejected root-level session refresh.

Only active and recovering incidents contribute to the unreviewed counter. A
recovering upload with current process-owned payload progress is informational;
the same queued retry remains an error when that evidence is absent. A failed
mount-start request becomes resolved only when a newer authenticated mount start
proves recovery. A root-level HTTP 401 is kept separate from older
file-operation incidents and does not remain unreviewed after current runtime
checks prove authentication, mount and RC health. Routine bandwidth-control
notices do not enter issue review.
Automatically resolved incidents remain visible as a single informational
recovery record until they are marked reviewed. The review button remains
available when only these recovery records are waiting. Review rows are ordered
by their displayed event or recovery time with the newest first. A recovered
root-level session refresh keeps its displayed time anchored to the final related
401 log event instead of changing with each status poll. An old message or a path
merely disappearing from the queue is never enough to declare success.

Each retained incident shows its local timestamp, severity, category, affected
path or component, sanitized rclone context and a suggested next step. Its
occurrence label describes related records in the retained recent log window;
the count may decrease as old records leave that bounded window and is not a
lifetime total. API URLs, Proton share/link identifiers and credential-shaped
values are redacted before entering the JSON snapshot. Only **Mark issues
reviewed** advances the watermark and hides reviewed incidents and recovery
records from issue review; it does not delete logs, watchdog history, transfer
history or current health warnings.

The Active, Queue and VFS-Cache overview cards provide keyboard and pointer
shortcuts into the corresponding Transfers sections. The cache
section distinguishes pending protected upload data from clean synced copies,
shows running versus saved retention and explains why a non-empty cache can be
healthy while the upload queue is empty.

Health history shows the latest 24 samples in the Control Center. The state
adapter exposes at most 48 samples, while `pdrive-watch --record` keeps a bounded
512-entry on-disk history (about 32 days at the normal 90-minute interval).
Older entries are removed atomically after a new sample is recorded, so the
history file cannot grow indefinitely.

The overview keeps the upload and download-traffic graphs compact and side by
side. Both rates derive from Linux TCP payload counters belonging to the exact
PID reported by `rclone-proton-drive.service`. That keeps a stale rclone
transfer statistic from looking like live upload traffic after a failed
attempt. The receive side can include small Proton API and metadata replies,
but neither side can include browser traffic or another rclone mount.
Both graphs label zero, half peak and peak on the Y axis. Their X-axis window is
derived from the selected live-metrics interval and the 150 retained samples,
so changing the interval updates both the poll note and displayed time range.

The Queue card shows the complete remaining VFS backlog, subtracting bytes
already reported for each matching active transfer. Its ETA uses an
exponentially smoothed process-owned upload rate. When exactly one queued file
matches one active transfer, both views share that estimator, so they cannot
show contradictory speeds or completion times. PDrive waits for three useful
samples before showing a number. While useful bytes are flowing but the sample
window is still young it shows **ETA calculating**; without current traffic it
shows **⏸ ETA waiting**. It never turns an idle API request or a stale rclone
transfer counter into a precise completion promise. Normal estimates use `HH:MM:SS`, multi-day uploads
show days and hours, and extreme near-pause estimates above 100 days use a
rounded day count in compact cards. Hovering the value reveals the fuller
estimate.

A previous upload failure remains available in History and issue review while
the retry is being observed. After three fresh process-owned traffic samples,
the live banner changes from **Attention** to **Recovering**. It falls back to
the conservative warning when traffic becomes stale and never overrides an
unrelated critical condition.

The Capacity card separates the Proton account from the local cache filesystem.
It shows Proton cloud used, total and free values exposed by the mounted remote beside
local free space and current VFS-cache use. Remote capacity may contact the
backend, so it is read only at UI startup, every 15 minutes and when the user
requests a manual refresh; ordinary live polls reuse the last reading.

The Overview short status includes service uptime and the systemd restart
counter. History retains the deeper service snapshot: active/sub state, PID,
result and exit status, uptime, restart count, mount filesystem and the latest
watchdog state. Health history on disk is capped at 512 samples, the state
adapter exposes 48, and the UI renders the latest 24.

The control popover opens guarded operations, Preferences, an About dialog and
a native documentation window with Quick start, Everyday use, Operations,
Troubleshooting, Security and License pages. Account reauthorization appears
there only while PDrive has detected that the configured account requires it;
the same contextual action is shown in the Overview status banner.
Intentional account migration is separate: **Preferences → Account → Change
Proton account …** is always available on a configured installation and opens a
full native login plus explicit migration confirmation.
The About dialog reports the
installed PDrive Control Center version, project authors, GPL license and
canonical GitHub project link.
Selecting any popover action closes the menu before its dialog or operation
starts, so stale controls never remain open behind another window.
Its **License** action opens the complete locally installed GPL text in the
native documentation viewer, without requiring a browser or network access;
software updates remain the responsibility of the documented installer or
future system package manager. The documentation viewer prefers
`$XDG_DATA_HOME/doc/proton-drive-linux`, then conventional
`/usr/share/doc/proton-drive-linux` package files and finally a development
checkout. Quick start through Security render headings, lists, tables,
quotations, GitHub callouts, code, local project images and links through GTK
without WebKit or another runtime dependency. License is deliberately shown as
literal plain text so its punctuation can never be interpreted as Markdown.
Remote badge images are not fetched. The popover is constructed
with visible child widgets but remains closed until the user activates its
header button.

`--check` validates GTK and locates `pdrive-state` without opening a window.

### Control Center settings reference

This is the complete reference for every setting exposed by PDrive Control
Center. Open the hamburger menu in the title bar for global Preferences and
guarded actions. Click a row in the Overview **Configuration** card for its
matching operational setting. Every operational setting is also available in
the hamburger menu; **Cache retention** additionally appears in **Transfers →
Local VFS cache**.

Apply and Save remain unavailable until a value actually differs from the
current value. Cancel closes a dialog without changing files or the running
service.

#### Preferences

Open **hamburger menu → Preferences**. These settings do not change rclone,
upload safety or watchdog recovery decisions. The notification choice is read
by the independent watchdog even while the Control Center is closed.

| Setting                                 | Choices and default                                              | Behavior                                                                                                     |
| --------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Keep running in tray on window close    | Off / On; default **Off**                                        | On hides the window instead of quitting the UI. The mount service continues either way.                      |
| Start hidden with the desktop session   | Off / On; default **Off**                                        | Creates PDrive's marked Cinnamon autostart entry and implies close-to-tray. Manual launches open.            |
| Keep live metrics updating while hidden | Off / On; default **Off**                                        | On continues two-second-style UI polling in the tray. Off saves resources; the watchdog continues.           |
| Desktop notifications                   | **Important**, Critical only, All, or Off; default **Important** | Important reports warnings, critical failures and recovery actions but suppresses routine ready transitions. |
| Live metrics interval                   | **1, 2, 5 or 10 seconds**; default **2**                         | Changes UI cards and graph sampling immediately after Save. It does not change the 90-minute watchdog.       |
| Language                                | **English** or **Deutsch**; default **English**                  | Saved immediately; visible text changes after quitting and reopening the Control Center.                     |

Preferences are written atomically to mode-0600
`~/.config/pdrive-ui.json`. Enabling session startup atomically manages
`~/.config/autostart/io.github.claudiuschuster.PDriveControl.desktop`, marked
with `X-PDrive-Control-Center=true`, whose command is `pdrive-ui --background`.
The application refuses to overwrite a same-named unmarked file and removes
only its own marked autostart file. A manual menu launch remains visible.

The Preferences **Account** section is a guarded action rather than a saved UI
preference. **Change Proton account …** accepts a new Proton username or email,
password and an optional fresh six-digit 2FA code. It has no
default credential value and stores none of those inputs in the UI preference
file. Activation occurs only after isolated authentication, a repeated clean
preflight and validated remounting. Its persistent effects are the encrypted
`~/.config/rclone/rclone.conf`, the mode-0600 opaque namespace selector
`~/.config/pdrive-account.conf`, a new owner-only cache root below
`~/.cache/rclone/accounts/`, and an encrypted rollback bundle below
`~/.config/rclone/backups/`. The complete safety and rollback contract is in
**Guarded Proton account switching** below.

#### Operational settings

These dialogs delegate to the same strict `pdrive-*` helpers available in a
terminal. The UI never edits rclone's encrypted configuration directly.

| Control and location                       | Range and default                                              | When it takes effect and what it changes                                                                                                                                     |
| ------------------------------------------ | -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Bandwidth** — Configuration or menu      | Upload and Download: `0.02`–`100 MiB/s`; default **Unlimited** | Applies independent bulk file-data limits live without restarting or closing a transfer. Metadata/API requests stay outside them; full right removes that direction's limit. |
| **Upload slots** — Configuration or menu   | **1–8**; default **4**                                         | Saves parallel file-upload count for the next controlled service start; it does not restart rclone.                                                                          |
| **Metadata cache** — Configuration or menu | Disabled / Enabled; default **Disabled**                       | Saves the exclusive Proton metadata mode for the next controlled service start. Enable only for one active writer.                                                           |
| **Cooldown** — Configuration or menu       | **1–168 hours**; default **12 hours**                          | Changes the watchdog's automatic-recovery policy immediately; it does not restart rclone or clear an active cooldown.                                                        |
| **Cache retention** — Transfers or menu    | **1–8760 hours**; default **24 hours**                         | Saves clean read-cache age for the next controlled service start. It never expires Dirty upload data.                                                                        |

Each dialog states whether a change is live or saved for the next service
start. The Transfers cache section also shows running and saved retention when
they differ. The detailed helper sections below document each setting's file
format, CLI equivalent and refusal conditions:

- bandwidth: `~/.config/pdrive-bwlimit.conf` and `pdrive-bwlimit`;
- upload slots: `~/.config/pdrive-transfers.conf` and `pdrive-transfers`;
- metadata cache: `~/.config/pdrive-recovery.conf` and `pdrive-recovery`;
- cooldown duration: `~/.config/pdrive-watch.conf` and `pdrive-watch`;
- cache retention: `~/.config/pdrive-cache.conf` and `pdrive-cache-age`.

#### One-shot actions

| Action                                                               | Protection and result                                                                                                                                                                                 |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Header **Refresh**                                                   | Re-reads local state immediately and refreshes Proton capacity; it changes no configuration.                                                                                                          |
| **Restart cooldown → Reset restart cooldown**                        | Clears only the current automatic-restart cooldown through `pdrive-watch --clear-cooldown`; the configured duration is unchanged.                                                                     |
| **Refresh metadata**                                                 | Checks uploads, queue and Dirty cache first, then requires terminal confirmation before a controlled restart.                                                                                         |
| **Safely restart service**                                           | Warns that an active upload would be interrupted, requires terminal confirmation and validates the new PID and mount.                                                                                 |
| **Mark issues reviewed**                                             | Advances only the local issue watermark and clears reviewed issues or recovery information from issue review; it does not delete logs, history or unresolved health evidence.                         |
| **Open Proton Drive web**                                            | Opens the official web client for account-wide settings; it makes no local PDrive change.                                                                                                             |
| **Open PDrive folder**                                               | Opens `/pdrive` in the file manager; reads and writes then follow normal mounted-filesystem semantics.                                                                                                |
| Overview banner or conditional menu **Reauthorize Proton account …** | Appears only when PDrive reports `reauthorization-required`; runs one isolated same-account login and replaces the encrypted configuration only after Proton accepts it.                              |
| **Preferences → Account → Change Proton account …**                  | Always-distinct intentional migration; refuses active or pending work, authenticates in isolation, selects a new cache namespace and rolls back all live selectors if the new mount fails validation. |

Metadata refresh and service restart deliberately finish their final safety
checks in a terminal so the user sees the exact queue state and confirmation
word. The other setters report helper failure in the UI and name the equivalent
command to run for full diagnostics.

### Window and tray behavior

Window geometry is deliberately not persisted. Every launch starts at a compact
820-pixel content width and grows vertically to show the complete Overview when
the monitor allows it. This avoids a vertical scrollbar caused by stale geometry
or a one-pixel theme difference while remaining independent of GTK shadow and
header-bar dimensions. A session-autostart window stays hidden until the user
opens it; hidden, unmapped allocations are never used for content fitting.
Opening it restores the compact content height before the same visible-window
fit runs. Each opening can request at most one growth resize after the first
dashboard state arrives, so an allocation that has not caught up cannot add the
same overflow repeatedly. Smaller screens retain normal scrolling.

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
pdrive-bwlimit 0.02
pdrive-bwlimit off
```

A single value means upload limit with unlimited download. A colon separates
upload and download. Every unitless numeric component receives the rclone `M`
suffix before validation, so `4:1` becomes `4M:1M`. Values are bytes per second,
not bits per second.

The Control Center exposes separate logarithmic sliders for both directions.
Each far-right endpoint is **Unlimited (`off`/`0`)**, because rclone normalizes
a zero bandwidth limit to unlimited throughput. Upload's far-left **⏸ ≈0**
endpoint applies `0.02 MiB/s`: this is an intentional near-zero throttle, not a
native VFS pause. The active upload remains open and resumes normal throughput
as soon as the slider is moved or its limit is removed.

The helper uses a short-lived loopback rclone only to canonicalize rate syntax,
writes one mode-0600 config atomically, then calls the running Proton backend's
`data-bandwidth` command through the owner-only Unix socket. Its shared upload
and download token buckets wrap only file payload readers. Directory listings,
authentication and other Proton API metadata bypass those buckets.

At service start, the mount is created first and `ExecStartPost` applies the
saved pair. The limits are deliberately not passed as backend command-line
options: backend options participate in rclone's VFS cache fingerprint, and a
different fingerprint could temporarily hide an existing Dirty upload queue.
Runtime application preserves the original namespace and never restarts the
transfer.

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

PDrive normally detects the terminal backend message that a fresh 2FA login is
required. `pdrive-auth-failure-guard` correlates it only with log output from
the current service start, writes mode-0600
`~/.local/state/rclone/pdrive-auth-state.json`, cancels the pending
`Restart=on-failure` retry and sends one notification according to the Control
Center notification preference. It never records a username, password, TOTP,
API URL or session token. The Overview then shows **Reauthorization required**
with a dedicated button; only while this state is active, the same action is
available under **hamburger menu → Reauthorize Proton account …**. Both actions
disappear again after successful reauthorization. A rate-limit state keeps the
action unavailable until its saved cooldown expires.

The native dialog uses the account already present in the encrypted
configuration and requests only the current account password and optional fresh
six-digit 2FA code. It performs exactly one bounded attempt. The password and
code fields are cleared immediately; their encoded mutable buffer crosses an
anonymous stdin pipe and is overwritten after the helper returns. They never
enter argv, the environment, state JSON or screenshots. A rejected login keeps
the old configuration and the stopped retry guard intact. A successful login
backs up and atomically replaces the encrypted configuration, clears the
one-time code, starts `/pdrive` and changes the authentication state to ready.

Only concrete HTTP 429 evidence in the private isolated-login log activates the
rate-limit state; generic login rejection and HTTP 422 do not. PDrive stores a
credential-free `retry_after` timestamp with a conservative one-hour cooldown,
shows it in the Overview, turns the dialog into a Close-only explanation and
blocks the hamburger-menu and direct-service-start bypasses. When the timestamp
expires, the normalized state automatically offers reauthorization again. A
successful isolated login clears either terminal state immediately.

The equivalent terminal fallback remains:

```bash
pdrive-reauth
pdrive-reauth --reauth
```

The no-option form is help only. Use `--reauth` exclusively for an expired or
invalid session, a changed Proton password, or a diagnosis that clearly points
to authentication.

The helper requires `REAUTH`, reuses the existing account name and silently
reads the current password twice plus an optional current TOTP. It transports
an empty account override and both secrets through an anonymous stdin pipe to a
narrow internal backend; credentials never appear in process arguments or
environment variables.

The backend builds a separate encrypted candidate configuration and performs
exactly one bounded, read-only login using a dedicated temporary cache. A failed
login leaves the existing encrypted configuration and running mount untouched.
Only after a successful test does it stop the service, back up the final current
`rclone.conf`, remove the one-time TOTP, atomically install the replacement and
start and validate the mount. Temporary configuration and cache paths are
removed on every exit. Documented non-session backend choices such as an
obscured two-password mailbox value and custom encoding are preserved; old
client/session tokens are deliberately not copied into the candidate.

After HTTP 429, leave the service stopped until the retry time shown by PDrive.
If Proton states a longer backoff, that longer interval remains authoritative.
Repeated “tests” can extend the block.

## Guarded Proton account switching

Same-account reauthorization and account switching are intentionally separate.
Reauthorization preserves the existing account identity and VFS namespace;
`pdrive-account-switch --switch` deliberately changes both. The Control Center
access path is **hamburger menu → Preferences → Account → Change Proton account
…**. Its full native form accepts the candidate username or email, password,
and optional fresh six-digit 2FA code. The explicit checkbox
confirms that `/pdrive` and the Proton remote namespace will change while old
local cache data remains separate.

The no-option and `--help` terminal forms are action-free:

```bash
pdrive-account-switch
pdrive-account-switch --switch
```

Before presenting terminal credentials, and again immediately after the
bounded candidate login, the backend requires all of these facts:

- no active upload or download in `core/stats`;
- an empty live `vfs/queue` whenever the managed service is active;
- no Dirty VFS metadata anywhere below the retained legacy or account-specific
  cache roots;
- a coherent service/mount/owner-only RC state that can be inspected safely.

An unavailable queue, malformed metadata, an unexpected mount, a changing
service state or any pending work is a refusal, not permission to guess. The
current service, configuration, authentication state and every cache file stay
untouched. This repeated preflight closes the race in which a transfer begins
while Proton validates the candidate login.

Credentials cross one anonymous NUL-delimited stdin pipe. They never enter
process arguments, environment variables, persistent logs, state JSON,
fixtures, diagnostics or screenshots. The candidate configuration is encrypted
with the existing GNOME-Keyring-backed rclone configuration password and tested
once with retries bounded and a dedicated temporary cache. Account-specific
mailbox secrets, session tokens and current-account backend credentials are not
copied. The one-time 2FA field is removed before any candidate can become live.
A rejected or rate-limited candidate does not change the same-account
reauthorization guard or its saved cooldown.

Only after authentication and the second preflight does PDrive stop the managed
service. It saves the final encrypted `rclone.conf`, the prior opaque account
selector and the credential-free authentication state in a mode-0700 rollback
bundle. The candidate receives a random `account-` plus 32-hex namespace; the
identifier contains no username, email, Proton ID or remote path. The selector
is written atomically to mode-0600 `~/.config/pdrive-account.conf`, and
`rclone-proton-mount` resolves it to
`~/.cache/rclone/accounts/<opaque-namespace>`. An installation without the
selector continues using the legacy `~/.cache/rclone` root, so an upgrade never
hides existing Dirty data.

Success requires the user service to be active, `/pdrive` to be a writable
rclone FUSE mount, the owner-only RC socket PID to match systemd, and `vfs/stats`
to report both data and metadata paths below the new cache root. If any gate
times out, PDrive stops the candidate, atomically restores the previous
encrypted configuration, account selector and authentication state, and—when
it was previously active—validates the old mount again. It never merges,
renames, deletes or reassigns either cache namespace. A rollback whose old mount
also cannot become ready leaves both namespaces intact and directs the user to
`pdrive-doctor`.

Previous account cache roots and rollback bundles are deliberately retained.
They can contain the only local copy of important data even after a clean
preflight. Do not delete them merely to reclaim space; first identify the exact
namespace, prove it has no Dirty metadata, verify important remote files in the
corresponding account and maintain an independent backup.

## Advanced draft recovery

```bash
pdrive-draft-recovery
pdrive-draft-recovery --enable
pdrive-draft-recovery --disable
pdrive-draft-recovery --recover-now
```

`pdrive-draft-recovery.timer` checks every five minutes for the exact failure
where an incomplete server-side upload draft blocks the same locally queued
file. It remains inactive in parallel-client-compatible metadata mode. In
exclusive metadata-cache mode it still requires all of these independent
signals before changing anything:

- the same queue item has failed at least twice;
- a log line explicitly reports an existing upload draft for that queued cache
  object; the evidence remains bound to its metadata inode rather than expiring
  while a very large upload is still the same queue generation;
- a later retry confirms the same privacy-preserving item fingerprint;
- a 20-second activity probe finds no meaningful TCP payload, rclone transfer
  progress, process reads or filesystem I/O;
- the live and calculated VFS namespaces agree;
- Dirty VFS metadata contains at least the complete queued byte count;
- no target namespace exists that would require an unsafe directory merge.

After confirmation, the helper stops only the mount service, atomically renames
both VFS data and metadata directories, enables draft replacement and validates
that the restarted mount exposes the preserved queue from the exact recovery
namespace. It never copies, truncates or deletes pending content. If any step
fails, it restores the original configuration and namespace before restarting
the conservative mount. When the queue and all Dirty metadata become empty, a
later timer run performs the same guarded round trip back to normal behavior.

The recovery namespace has its own stricter second-stage stall guard. A queued
file, old age, low traffic or long ETA never qualifies by itself. One controlled
restart is possible only when all of these conditions apply to the same
name/size/metadata-inode cache generation:

- at least 1 MiB of matching per-file transfer progress was already observed;
- a later path-specific 401, 404, 422, 5xx or upload-retry error exists;
- no still-newer transfer progress has made that error obsolete;
- upload bandwidth is above the 64 KiB/s near-pause safety threshold;
- the service, owner-only RC endpoint and DNS resolution are healthy;
- two 20-second probes at least two minutes apart measure no meaningful TCP,
  rclone-transfer, process-read or filesystem-read delta;
- the recovery flag, calculated live namespace, complete Dirty byte count and
  exact fingerprint still match immediately before the restart;
- this cache generation has never received its one allowed guarded restart.

The restart stays inside `replace_existing_draft=true`; it does not rename,
copy, truncate or delete cache data. Before systemd is called, the attempt is
persisted atomically so an interrupted helper cannot repeat it. Success requires
a new PID, the recovery runtime flag, the same VFS namespace and the exact
protected queue generation to reappear. A validation failure consumes the
single attempt and remains visible for manual review. A PID change requires
fresh progress and error evidence; restored payload traffic, a near-pause
throttle or DNS outage resets the stall confirmations instead of restarting
rclone.

Payload completion and Proton finalization are separate phases. A transfer at
100% means all encrypted payload blocks were sent; it is not successful until
Proton commits the remote revision and rclone removes the item from the VFS
queue. The helper therefore reports `finalizing` without restarting when a
matching queue item has reached its complete size normally.

A finalization restart is a separate, single-use allowance for the exact cache
generation. It is considered only when a 401, 404, 422 or 5xx backend error is
bound to the completion window, the installed rclone contains the upstream
fresh-stream retry fix, the upload limit is not near pause, DNS and the service
are healthy, the ten-minute commit grace has elapsed, and two separated
20-second probes still find no activity. A recent payload-recovery restart adds
a 30-minute gap. The finalization attempt is persisted before systemd is called
and never deletes or relocates the Dirty VFS payload.

Relevant finalization states are `finalizing`, `confirming-finalization`,
`finalization-cooldown`, `finalization-restarted`,
`finalization-restart-limited` and `upgrade-required`. The last state means the
queued payload is being preserved because the installed rclone does not yet
contain the safe retry behavior.

### Proton bridge worker-stall recovery

Repeated HTTP 502 failures while encrypted blocks are uploaded can leave the
current Proton API bridge process with no available block-upload workers. The
rclone process and VFS queue then remain present, but the transfer produces no
TCP or payload progress. This is different from both an ordinary VFS stall and
the final commit phase.

The helper recognizes this narrow signature only after all of the following
evidence belongs to the same process and exact cache generation:

- matching payload progress was proven before the failure;
- either at least three path-correlated HTTP 502 block-upload cycles occurred
  at least 30 seconds apart, or two such cycles were followed by a terminal
  `This file has been removed` response in the same or a later log second;
- the newest failure is later than the newest payload progress;
- upload bandwidth is above near pause and DNS is healthy;
- two 20-second activity probes at least two minutes apart remain idle;
- the fixed rclone version, recovery flag, namespace, Dirty byte count, queue
  and generation fingerprint still pass the normal restart validation.

This stage has a separate budget of six controlled restarts per exact cache
generation and a minimum 30-minute gap. Its counters never consume or bypass
the one ordinary payload restart or the one finalization restart. Active
traffic, a process change, near-pause bandwidth or unhealthy connectivity
clears pending confirmations without consuming the budget. Reaching the limit
leaves the complete Dirty cache protected for manual review.

The two-cycle terminal variant avoids a recovery deadlock: once Proton has
removed the failed remote draft, the block worker may become fully idle and can
no longer emit a third 502 cycle. A single 502, an older 404, or two ordinary
server errors remain insufficient and fall back to the conservative normal
limits.

Relevant states are `probing-bridge-stall`, `confirming-bridge-stall`,
`bridge-cooldown`, `bridge-restarted` and `bridge-restart-limited`. The Control
Center shows the observed failure cycles and the independent restart budget in
**History → Service diagnostics → Draft recovery**.

The automatic path deliberately needs two observations. `--recover-now` skips
only that waiting period; every cache, namespace, exclusivity and rollback guard
still applies. It is useful after a human has already verified the exact draft
conflict. Status and logs are available without remote listing:

```bash
systemctl --user status pdrive-draft-recovery.timer
journalctl --user -u pdrive-draft-recovery.service -n 100 --no-pager
jq . ~/.local/state/rclone/pdrive-draft-recovery-latest.json
```

The Control Center mirrors that latest secret-free state under **History →
Service diagnostics → Draft recovery**. The persistent internal file
`pdrive-draft-recovery-state.json` contains only hashes, counters, categories
and timestamps—never a path, credential, API URL or Proton identifier.

The older `--enable`/`--disable` controls remain available for audited manual
recovery. They intentionally do not restart rclone or relocate cache data.
Never use them without separately verifying the complete Dirty payload and
exact namespace. Read the draft section in
[Troubleshooting](TROUBLESHOOTING.md) before manual use.

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
computer was off. New installations currently download the pinned
`pdrive-v1.76.0-beta.10204.2` x86-64 asset from the public OSS Singularity
rclone release. `pdrive-prerequisites` verifies the embedded SHA-256 digest,
minimum upload-safe version and required Proton backend command before atomic
installation. The updater invokes that same verifier and does not follow
rclone's official stable channel, because an otherwise newer binary may lack
PDrive's source-reviewed file-data limiter, bridge-worker fix and bounded
failed-block retry. Their upstream review and dependency order are tracked in
[rclone #9832](https://github.com/rclone/rclone/issues/9832) and
[Proton-API-Bridge #8](https://github.com/rclone/Proton-API-Bridge/pull/8), with
the retry follow-up recorded in
[PDrive #42](https://github.com/oss-singularity/proton-drive-linux/issues/42).
A newly installed binary is intentionally left for the next natural mount
start; the updater never restarts an active transfer.

The optional official Proton Drive CLI timer runs five minutes after boot when
due and daily with up to four hours of randomized delay. Its updater accepts
only the parsed official `proton.me` x86-64 version URL, downloads over TLS and
atomically replaces the binary only after the release page's SHA-512 value
matches. This CLI is separate from the rclone FUSE mount.

Both updater services use fixed per-machine jitter, explicit time limits, a
private umask, low CPU/I/O priority and a restricted systemd sandbox. They can
write only their intended user-local binary/state locations. The watchdog uses
a similarly bounded read-mostly sandbox. These restrictions are deliberately
not copied to `rclone-proton-drive.service`: FUSE, `fusermount3`, GNOME Keyring,
the mount namespace and the VFS cache require capabilities that generic service
hardening can accidentally block.

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
  pdrive-watch.timer pdrive-draft-recovery.timer rclone-selfupdate.timer
pdrive-doctor
```

Do not start the service until `pdrive-doctor` can unlock the configuration and
the cache/Dirty state is understood. A restored VFS cache can contain the only
complete copy of pending writes; never merge, rename or delete cache namespaces
blindly. If the Keyring password is unavailable, restore both parts from the
same backup or create a fresh encrypted configuration with `pdrive-setup`; the
old encrypted file cannot be recovered from its ciphertext alone.
