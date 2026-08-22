# Proton Drive Linux Mount Toolkit

An opinionated, user-local Proton Drive mount for Linux Mint Cinnamon, built
around rclone's Proton Drive backend. It integrates a writable FUSE mount into
Nemo, starts after desktop login, keeps the rclone configuration encrypted in
GNOME Keyring, updates itself, and ships diagnostics for the failure modes that
matter during large uploads.

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
  jq curl openssl iproute2 libnotify-bin
sudo apt-mark manual \
  fuse3 libfuse3-3 libsecret-tools gnome-keyring \
  libpam-gnome-keyring jq
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

## Command overview

The tools intentionally distinguish read-only status from state-changing
actions. Every `--help` path is action-free.

| Command | Default behavior | Explicit changes |
| --- | --- | --- |
| `pdrive-setup` | Show setup help | `--setup` creates the first encrypted remote |
| `pdrive-doctor` | Detailed local diagnosis | `--online` performs one bounded API listing |
| `pdrive-watch` | Fresh health report | Cooldown controls and confirmed service restart; `--record` is for the timer |
| `pdrive-bwlimit` | Show persistent and live limit | Set a limit or use `off`, live without restart |
| `pdrive-recovery` | Show Proton metadata-cache mode | `--enable` or `--disable` for the next service instance |
| `pdrive-refresh` | Show cache, queue and Dirty state | `--refresh` safely rebuilds all metadata after external changes |
| `pdrive-draft-recovery` | Show dangerous draft-replacement mode | Explicit enable/disable with Dirty-queue guards |
| `pdrive-transfers` | Show configured and running upload slots | Set `1` to `8`, or `default`, for the next start |
| `pdrive-reauth` | Show emergency-login guidance | `--reauth` performs one confirmed session renewal |

Detailed command behavior is documented in [Operations](docs/OPERATIONS.md).

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
is active.

## Uninstall

```bash
./uninstall.sh --uninstall
```

The uninstaller refuses to proceed with queued or Dirty VFS data and asks for
the exact confirmation `UNINSTALL`. It removes only managed programs, docs and
units. Personal rclone configuration, Keyring secret, cache, logs and `/pdrive`
are retained deliberately so recovery remains possible.

## Repository layout

```text
bin/             user-facing pdrive commands and the Keyring rclone wrapper
libexec/         mount, unmount, setup and updater implementations
systemd/user/    mount, monitor and update user units
docs/            operations and troubleshooting handbook
tests/           static, privacy and action-free-help checks
install.sh       idempotent user-local installer
uninstall.sh     guarded removal of repository-managed files
```

## Development

```bash
make check
```

The checks validate Bash syntax, ShellCheck findings, systemd units when the
local validation prerequisites exist, action-free help behavior and the absence
of deployment-specific paths or secrets.

## Security and limitations

- The rclone configuration is encrypted, but the unlocked desktop session can
  access its Keyring item by design.
- The RC API has no application password; it is restricted to a mode-0600 Unix
  socket in the user's state directory and is never exposed on TCP.
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
