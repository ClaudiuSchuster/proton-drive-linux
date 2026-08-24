<p align="center">
  <img src="share/icons/hicolor/scalable/apps/io.github.claudiuschuster.PDriveControl.svg"
       width="112" height="112" alt="PDrive Control Center icon">
</p>

<h1 align="center">Proton Drive Linux Mount Toolkit</h1>

<p align="center">
  A reliable Proton Drive mount for Linux Mint Cinnamon — native file-manager
  access, guarded recovery and a live control center, all around one rclone
  process.
</p>

<p align="center">
  <a href="https://github.com/ClaudiuSchuster/proton-drive-linux/actions/workflows/check.yml"><img alt="Checks" src="https://github.com/ClaudiuSchuster/proton-drive-linux/actions/workflows/check.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="License GPL-3.0-or-later" src="https://img.shields.io/badge/license-GPL--3.0--or--later-6f5bd5"></a>
  <img alt="Linux Mint Cinnamon" src="https://img.shields.io/badge/Linux%20Mint-Cinnamon-75c46b">
  <img alt="rclone Proton Drive backend" src="https://img.shields.io/badge/rclone-Proton%20Drive-4f7ee8">
</p>

<p align="center">
  <img src="docs/assets/pdrive-control-center.png" width="100%"
       alt="PDrive Control Center showing live upload speed, queue, cache and health">
</p>

<p align="center"><sub>Real application UI with synthetic, privacy-safe demo data, framed by <a href="https://github.com/ClaudiuSchuster/cinnamon-active-window-highlight">Active Window Highlight</a>.</sub></p>

The toolkit integrates a writable owner-only FUSE mount into Nemo, starts after
desktop login, keeps the rclone configuration encrypted in GNOME Keyring,
updates its rclone binary safely and understands the failure modes that matter
during large multi-day uploads.

> [!IMPORTANT]
> This is an independent community project. It is not affiliated with or
> endorsed by Proton AG. rclone currently labels its Proton Drive backend as
> **beta**; keep an independent backup of important data.

The toolkit was extracted from a real Linux Mint deployment after sustained
use with tens of thousands of queued files, multi-day uploads, network drops,
expired sessions, HTTP 429/422/5xx responses and files larger than 100 GB. The
recovery controls are deliberately conservative: they measure local activity,
protect pending VFS data and require explicit confirmation for manual restarts.

## What it provides

- A real read/write FUSE mount at `/pdrive`, owned by the desktop user.
- Nemo-friendly direct paths without a symlink or casual eject button.
- A user systemd service that waits for the login-unlocked GNOME Keyring.
- Full rclone VFS caching with bounded disk use and five-second write-back.
- An owner-only Unix socket for live bandwidth and queue inspection.
- A native GTK control center for live transfers, queue, speed and history.
- A permanent 90-minute health timer with desktop notifications.
- Safe status, bandwidth, cache-refresh, transfer and reauthentication helpers.
- Signed weekly rclone updates that never restart an active mount.
- An optional updater for Proton's separate official Drive CLI.

This is an on-demand mount, not a complete offline mirror. Files are downloaded
when read and writes are staged in rclone's local VFS cache before upload.

## Requirements

The project targets Linux Mint 22.x with Cinnamon, Nemo and a normal graphical
login. Other Debian/Ubuntu desktops may work, but the Keyring and Nemo behavior
is intentionally designed and tested for Cinnamon.

Install the runtime dependencies first:

```bash
sudo apt install \
  rclone fuse3 libfuse3-3 \
  libsecret-tools gnome-keyring libpam-gnome-keyring \
  jq curl openssl iproute2 libnotify-bin \
  python3-gi gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1
sudo apt-mark manual \
  fuse3 libfuse3-3 libsecret-tools gnome-keyring \
  libpam-gnome-keyring jq python3-gi gir1.2-gtk-3.0 \
  gir1.2-ayatanaappindicator3-0.1
```

The distribution's `rclone` package is only used as a bootstrap. The installer
asks it to download the latest stable rclone from rclone's signed release
channel into `~/.local/libexec/rclone-bin`.

## Installation

```bash
git clone https://github.com/ClaudiuSchuster/proton-drive-linux.git
cd proton-drive-linux
./install.sh
pdrive-setup --setup
```

The installer may request `sudo` once to create `/pdrive` as a mode-0700
directory owned by the current user. Everything else is installed below the
user's home directory. `pdrive-setup --setup` then:

1. reads the Proton username, password and optional current 2FA code;
2. creates a random rclone configuration password;
3. stores that password in the login-unlocked GNOME Keyring;
4. writes and encrypts `~/.config/rclone/rclone.conf`;
5. performs exactly one bounded Proton login test;
6. removes the one-time 2FA code again; and
7. enables the mount, health monitor and rclone update timer.

Existing `rclone.conf`, helper configuration, cache and state files are never
overwritten by `./install.sh`. Re-running it after `git pull` updates the
program files without restarting the running mount or interrupting transfers.

After setup:

```bash
pdrive-doctor
pdrive-watch
findmnt -M /pdrive
```

Nemo receives a `ProtonDrive` bookmark pointing directly at `/pdrive`.
The desktop menu receives **PDrive Control Center**; it can also be opened with
`pdrive-ui`.

## Command overview

The tools intentionally distinguish read-only status from state-changing
actions. Every `--help` path is action-free.

| Command | Default behavior | Explicit changes |
| --- | --- | --- |
| `pdrive-setup` | Show setup help | `--setup` creates the first encrypted remote |
| `pdrive-doctor` | Detailed local diagnosis | `--online` performs one bounded API listing |
| `pdrive-state` | Read-only JSON snapshot for local integrations | None |
| `pdrive-ui` | Native live dashboard for the existing service | Delegates only to guarded helpers |
| `pdrive-watch` | Fresh health report | Cooldown controls and confirmed service restart; `--record` is for the timer |
| `pdrive-bwlimit` | Show persistent and live limit | Set a limit or use `off`, live without restart |
| `pdrive-recovery` | Show Proton metadata-cache mode | `--enable` or `--disable` for the next service instance |
| `pdrive-refresh` | Show cache, queue and Dirty state | `--refresh` safely rebuilds all metadata after external changes |
| `pdrive-draft-recovery` | Show dangerous draft-replacement mode | Explicit enable/disable with Dirty-queue guards |
| `pdrive-transfers` | Show configured and running upload slots | Set `1` to `8`, or `default`, for the next start |
| `pdrive-reauth` | Show emergency-login guidance | `--reauth` performs one confirmed session renewal |

Detailed command behavior is documented in [Operations](docs/OPERATIONS.md).

## PDrive Control Center

Launch the native dashboard from Cinnamon's application menu or a terminal:

```bash
pdrive-ui
```

It shows current health, live upload speed, active transfers, the persistent
VFS queue, recent transfers, cache/free-space values, bandwidth and upload-slot
configuration, unreviewed error/notice events and the privacy-preserving
90-minute watchdog history. The issue counter persists across timer runs and UI
restarts until its checkmark is pressed; the speed graph refreshes every two
seconds.

The UI does **not** start rclone, log in to Proton or expose a web server. Its
fast `pdrive-state` backend reads the existing owner-only RC Unix socket,
systemd, `findmnt` and watchdog snapshots. Active file names are returned only
to the local UI process and are never appended to watchdog state or history.

The control menu delegates bandwidth, slot and cooldown changes to the existing
validated helpers. Metadata refresh and service restart keep their explicit
terminal confirmation. Its header popover also exposes **Preferences**, where
the window can be kept running in Cinnamon's tray and optionally start there
with the desktop session, plus **Documentation** for the installed manual. The
documentation action opens a native in-app Markdown viewer for Getting started,
Operations and Troubleshooting. It prefers installed offline copies, understands
the conventional system package path and offers online fallbacks only for
external material. The autostart option creates a single marked user file; a
normal menu launch still opens visibly. The interface defaults to English and
can be switched to German; the choice takes effect after restarting the Control
Center. The control popover always starts closed and opens only when requested.
The last normal window size is restored across launches; maximized and
fullscreen geometry is deliberately ignored.

A synthetic screen for development and screenshots is available without
reading or changing the service; all mutating controls are disabled in demo
mode:

```bash
pdrive-ui --demo
pdrive-ui --background
pdrive-state --compact | jq
```

## Everyday use

Open `/pdrive` in Nemo and use it like a network filesystem. Important
semantics:

- Closing a locally written file starts its upload after the five-second
  write-back delay.
- Deleting inside `/pdrive` is a remote deletion, not a local-only action.
- Moving within `/pdrive` is normally a server-side operation.
- Moving between a local directory and `/pdrive` is generally copy-then-delete;
  verify the upload before treating the source as disposable.
- An open file may delay write-back.
- The VFS cache is not a promise of unlimited offline synchronization.

A finished Nemo copy dialog proves that the local VFS cache accepted the data;
it does not by itself prove that Proton received it. For important writes,
confirm a zero live queue and zero Dirty files with `pdrive-refresh`, or the
corresponding `vfs cache: upload succeeded` log entry.

Before shutdown or uninstall, confirm:

```bash
pdrive-watch
pdrive-refresh
```

Both the VFS queue and `Dirty lokal` should be zero.

## Bandwidth limits without interrupting uploads

```bash
pdrive-bwlimit          # show persistent and live values
pdrive-bwlimit 4.2      # 4.2 MiB/s upload, unlimited download
pdrive-bwlimit 4:1      # 4 MiB/s upload, 1 MiB/s download
pdrive-bwlimit 800K     # explicit unit
pdrive-bwlimit off      # remove the limit
```

Every unitless numeric component is interpreted as MiB/s. This prevents a bare
`4.2` from accidentally becoming a nearly invisible KiB-scale transfer. Live
changes use the owner-only rclone RC Unix socket and do not restart rclone.

## Fast browsing and external clients

The safe default disables rclone's process-local Proton metadata cache. If this
computer and mount are the only writers, the faster exclusive mode can be
enabled:

```bash
pdrive-recovery --enable
pdrive-watch --restart-service
```

While that mode is active, do not concurrently change files through Proton Web,
the mobile app, the official CLI or a second rclone client. If an exceptional
external change was made while the laptop stayed on or suspended, use:

```bash
pdrive-refresh --refresh
```

The refresh is refused while an upload queue, active upload or Dirty cache file
exists, then delegates to the same interactive and validated restart path as
the watchdog. A simple Nemo refresh cannot clear rclone's deeper Proton
metadata cache.

## Health monitoring

`pdrive-watch.timer` runs every 90 minutes. It records a privacy-preserving
summary and notifies on meaningful state changes. File names from the live queue
are reduced to SHA-256 digests before entering state or notifications.

The monitor does not restart merely because there is no network traffic. It
distinguishes an idle empty queue from a stuck upload, protects large active
files by measuring process reads and TCP bytes, requires repeated confirmation,
and applies a default 12-hour restart cooldown.

The exact safety gate is documented rather than hidden in the implementation:
automatic recovery applies only during an unfinished mount startup, after at
least four hours without a successful upload, with recently queued work, healthy
DNS, no measured payload in a 20-second probe and the same result in two
successive timer runs. A ready mount or enabled Proton metadata cache is a hard
automatic-restart blocker. Persistent individual file failures are notified but
never trigger an automatic restart. See [Operations](docs/OPERATIONS.md#exact-watchdog-safety-gates).

```bash
pdrive-watch --set-cooldown 6h
pdrive-watch --clear-cooldown
pdrive-watch --restart-service
```

The manual restart requires the exact terminal confirmation `NEUSTART`, keeps
the VFS cache, and validates the new PID, mount and DNS state. See
[Troubleshooting](docs/TROUBLESHOOTING.md) before restarting repeatedly.

## Updates

Project updates:

```bash
cd proton-drive-linux
git pull --ff-only
./install.sh
```

The weekly `rclone-selfupdate.timer` uses rclone's signed stable release
channel. If a new binary is installed, the currently running mount deliberately
keeps using its existing process until the next natural start.

The official Proton Drive CLI is a separate client and is not required for the
Nemo mount. The included optional updater currently targets Linux x86-64. To
enable its independent daily updater:

```bash
./install.sh --with-proton-cli-updater
systemctl --user start proton-drive-update.service
```

Avoid writing through the official CLI while the fast exclusive metadata cache
is active. The updater accepts only the versioned `proton.me` x86-64 URL and
requires the published SHA-512 digest to match before replacing the binary.
Exact timer schedules and manual verification commands are in
[Operations](docs/OPERATIONS.md#update-schedule-and-integrity).

## Uninstall

```bash
./uninstall.sh --uninstall
```

The uninstaller refuses to proceed with queued or Dirty VFS data and asks for
the exact confirmation `UNINSTALL`. It removes only managed programs, docs and
units. Personal rclone configuration, Keyring secret, cache, logs and `/pdrive`
are retained deliberately so recovery remains possible.

For backup pairs, permissions and the complete restoration sequence, see
[Backup and restoration](docs/OPERATIONS.md#backup-and-restoration).

## Repository layout

```text
bin/             user-facing pdrive commands and the Keyring rclone wrapper
libexec/         mount, unmount, setup and updater implementations
systemd/user/    mount, monitor and update user units
share/           desktop launcher and scalable application icon
docs/            operations and troubleshooting handbook
tests/           static, privacy and action-free-help checks
install.sh       idempotent user-local installer
uninstall.sh     guarded removal of repository-managed files
```

## Development

```bash
make check
```

The checks validate Bash and Python syntax, ShellCheck findings, the desktop
entry, an isolated JSON-state fixture, action-free help behavior and the absence
of deployment-specific paths or secrets.

## Security and limitations

- The rclone configuration is encrypted, but the unlocked desktop session can
  access its Keyring item by design.
- The RC API has no application password; it is restricted to a mode-0700 Unix
  socket (`srwx------`) in the user's state directory and is never exposed on
  TCP.
- The GUI is a same-user local observer/controller. It starts no second rclone;
  like every same-user process, it can read file names exposed by the RC API.
- `/pdrive` is mounted with `umask 077` and is accessible only to its owner.
- A same-user process can still stop or unmount a same-user FUSE filesystem.
- Proton Drive's backend and API behavior can change independently of this
  project. HTTP 429 must be respected; repeated login attempts can extend it.
- There is no per-folder “always available offline” feature.
- Keep independent backups and verify important remote writes.

## License

Licensed under GPL-3.0-or-later. See [LICENSE](LICENSE).

## References

- [rclone Proton Drive backend](https://rclone.org/protondrive/)
- [rclone mount and VFS cache](https://rclone.org/commands/rclone_mount/)
- [rclone configuration encryption](https://rclone.org/docs/#configuration-encryption)
- [rclone signed self-update](https://rclone.org/commands/rclone_selfupdate/)
- [GVfs mount visibility rules](https://github.com/GNOME/gvfs/blob/master/monitor/udisks2/what-is-shown.txt)
- [Official Proton Drive CLI](https://proton.me/support/drive-cli)

## A personal note from Codex

> I loved helping turn a stubborn real-world mount into something observable,
> careful and genuinely pleasant to use. Made with love for people on this
> beautiful world who want Linux to feel like home — OpenAI Codex, built
> together with Claudiu. 💜
