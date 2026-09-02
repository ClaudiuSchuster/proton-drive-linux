<p align="center">
  <picture>
    <img src="share/icons/hicolor/scalable/apps/io.github.claudiuschuster.PDriveControl.svg"
         width="112" height="112" alt="PDrive Control Center icon">
  </picture>
</p>

<h1 align="center">PDrive — Proton Drive for Linux</h1>

<p align="center">
  A careful Proton Drive mount for Linux desktops — native file-manager access,
  resilient uploads and a live GTK control center, all around one rclone
  process. Linux Mint is the reference platform; Arch and Ubuntu portability is
  underway.
</p>

<p align="center">
  <a href="https://github.com/oss-singularity/proton-drive-linux/actions/workflows/check.yml"><img alt="Checks" src="https://github.com/oss-singularity/proton-drive-linux/actions/workflows/check.yml/badge.svg"></a>
  <a href="https://github.com/oss-singularity/proton-drive-linux/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/oss-singularity/proton-drive-linux?display_name=tag&amp;sort=semver"></a>
  <a href="LICENSE"><img alt="License GPL-3.0-or-later" src="https://img.shields.io/badge/license-GPL--3.0--or--later-6f5bd5"></a>
  <img alt="Linux Mint Cinnamon" src="https://img.shields.io/badge/Linux%20Mint-Cinnamon-75c46b">
  <img alt="Arch and Ubuntu portability in progress" src="https://img.shields.io/badge/Arch%20%2B%20Ubuntu-in%20progress-6f5bd5">
  <img alt="rclone Proton Drive backend" src="https://img.shields.io/badge/rclone-Proton%20Drive-4f7ee8">
</p>

<p align="center">
  <img src=".github/social-preview.png" width="100%"
       alt="PDrive Control Center — Proton Drive at home on Linux">
</p>

<p align="center">
  <img src="docs/assets/pdrive-control-center.png?v=0.7.2" width="100%"
       alt="PDrive Control Center showing service health, realistic five-minute traffic graphs and storage capacity">
</p>

<p align="center"><sub>Proton Drive at a glance, framed by <a href="https://github.com/oss-singularity/cinnamon-active-window-highlight">Active Window Highlight</a>.</sub></p>

<table>
  <tr>
    <td><img src="docs/assets/pdrive-transfers.png" alt="PDrive Control Center transfer details"></td>
    <td><img src="docs/assets/pdrive-history.png" alt="PDrive Control Center issue review and health history"></td>
  </tr>
  <tr>
    <td align="center"><sub>Transfers, queue and protected VFS cache</sub></td>
    <td align="center"><sub>Reviewable issues, service diagnostics and bounded health history</sub></td>
  </tr>
</table>

<p align="center">
  <img src="docs/assets/pdrive-control-menu.png?v=0.7.3" width="282"
       alt="Healthy-state PDrive Control Center menu with transfer, cache, recovery and documentation actions">
</p>

Use Proton Drive directly in your file manager at `/pdrive`. The toolkit starts
the mount after desktop login, protects its encrypted rclone configuration with
GNOME Keyring and provides a native GTK control center for the details that
matter.

> [!IMPORTANT]
> This is an independent community project, not an official Proton product.
> rclone labels its Proton Drive backend as **beta**. Keep an independent backup
> of important data.

## Highlights

- Writable, owner-only `/pdrive` mount with a GTK file-manager bookmark.
- English and German GTK control center with tray support.
- Upload and download-traffic graphs with a configurable live interval.
- Active transfers, upload queue with a smoothed remaining-time estimate,
  service diagnostics, bounded health history and reviewable issue evidence.
- Clear Proton cloud used/total/free, local free-space and VFS-cache values.
- Independent upload/download file-data limits, guided connection tuning and
  guarded upload-slot, cache-retention, metadata-refresh and restart controls.
- Conservative health monitoring with desktop notifications.
- Guided first setup, contextual same-account reauthorization, guarded account
  switching with isolated cache namespaces, encrypted credentials and signed
  rclone updates.

This is an on-demand filesystem, not a full offline mirror. Reads download data
when needed; writes remain protected in the local VFS cache until uploaded.

## Install

The supported target is Linux Mint 22.x with Cinnamon, Nemo and a normal
graphical login. Arch Linux and Ubuntu are the first portability targets. The
Arch Linux `0.8.1-1` package candidate preserves the package baseline whose
`0.8.0-1` build passed its clean Cinnamon/X11 desktop gate. It is attached to
the `v0.8.1` GitHub Release for configured real-world review; Arch is not yet a
generally supported target. See the
[distribution portability plan](docs/PORTABILITY.md) and the privacy-safe
[real desktop release gates](docs/DESKTOP_GATES.md).

```bash
git clone https://github.com/oss-singularity/proton-drive-linux.git
cd proton-drive-linux
./install.sh
pdrive-ui
```

Arch reviewers can download the `proton-drive-linux-0.8.1-1-any.pkg.tar.zst`
asset from the [`v0.8.1` release](https://github.com/oss-singularity/proton-drive-linux/releases/tag/v0.8.1),
verify the SHA-256 published in its release notes and install it with:

```bash
sudo pacman -U ./proton-drive-linux-0.8.1-1-any.pkg.tar.zst
pdrive-ui
```

The native package installs immutable application files below `/usr` while
credentials, configuration, state, rclone and every VFS cache namespace remain
inside the user profile.

The installer may request `sudo` once to create the owner-only `/pdrive`
directory. On first launch, the setup wizard checks prerequisites, can install
missing supported distribution packages through Polkit, prepares PDrive's
verified Proton-capable rclone, offers automatic or manual connection headroom
and then guides you through username, password and optional 2FA. Automatic tuning uses a
bounded Cloudflare speed test and reserves capacity for browsing and other
applications. Credentials never appear in command arguments or environment
variables.

If Proton later requires a fresh login, PDrive stops automatic service retries,
shows one actionable notification and offers reauthorization directly in the
Control Center. The existing account name and protected VFS upload cache remain
untouched while the replacement login is verified. A real Proton rate limit is
distinguished from rejected credentials and persists a local retry time so no
UI or manual service start can create another premature login attempt.

For an intentional migration to another Proton account, open **Preferences →
Account → Change Proton account …**. PDrive refuses while any transfer, queued
upload or Dirty cache file remains, tests the candidate login in isolation, and
mounts it only through a fresh anonymous cache namespace. If activation fails,
the previous encrypted configuration, authentication state and cache namespace
are restored automatically.

<table>
  <tr>
    <td><img src="docs/assets/pdrive-account-settings.png" alt="PDrive Preferences account section with the guarded Change Proton account action"></td>
    <td><img src="docs/assets/pdrive-account-switch.png?v=0.7.7" alt="PDrive guarded Proton account-change dialog after a successful safety preflight"></td>
  </tr>
  <tr>
    <td align="center"><sub>A deliberate account action, separate from contextual reauthorization</sub></td>
    <td align="center"><sub>Full native credentials, explicit confirmation and cache-isolation promise</sub></td>
  </tr>
</table>

Existing configuration, credentials, cache and state are preserved when the
installer is run again.

<p align="center">
  <img src="docs/assets/pdrive-setup-wizard.png" width="700"
       alt="PDrive first-run wizard with automatic, manual and unlimited connection policies">
</p>

<p align="center"><sub>Approachable automatic tuning, with independent expert controls when wanted.</sub></p>

## Start using PDrive

Complete the first-run wizard, select **Open PDrive folder**, and work in
`/pdrive` through Nemo. A finished file-manager copy means the protected local
cache accepted the write; wait for zero Active transfers and an empty Queue
before treating it as remotely complete.

- [Quick start](docs/QUICK_START.md) — installation, first login, `/pdrive` and
  one verified upload.
- [Everyday use](docs/EVERYDAY_USE.md) — transfers, cache, notifications,
  bandwidth and safe routine operation.
- [Troubleshooting](docs/TROUBLESHOOTING.md) — symptom-led help when something
  looks wrong.

The same pages are available offline from **Menu → Documentation …** in the
Control Center. Detailed controls and maintenance remain in the
[Operations handbook](docs/OPERATIONS.md).

## Update

Until an APT/Software Manager release channel exists, update the toolkit with:

```bash
cd proton-drive-linux
git pull --ff-only
./install.sh
```

PDrive installs a pinned, checksum-verified rclone build published from its
public source fork. It contains the upstream fix for
[rclone #9722](https://github.com/rclone/rclone/issues/9722), the API bridge
worker fix proposed in
[Proton-API-Bridge #8](https://github.com/rclone/Proton-API-Bridge/pull/8), a
bounded retry of only transiently failed encrypted blocks tracked in
[PDrive #42](https://github.com/oss-singularity/proton-drive-linux/issues/42),
and the Proton file-data limiter tracked in
[rclone #9832](https://github.com/rclone/rclone/issues/9832). The limiter leaves
metadata browsing outside bulk transfer limits. The weekly updater stays on
that reviewed PDrive build until this project publishes a replacement and never
restarts an active mount. The optional official Proton Drive CLI is a separate
client and is not required by this project.

## Uninstall

```bash
./uninstall.sh --uninstall
```

Uninstall is refused while queued or Dirty VFS data exists. Personal rclone
configuration, Keyring secret, cache, logs and `/pdrive` remain available for
recovery unless you deliberately remove them later.

## Documentation and development

- [Quick start](docs/QUICK_START.md) — the shortest path from installation to a
  verified remote upload.
- [Everyday use](docs/EVERYDAY_USE.md) — concise guidance for normal Nemo and
  Control Center workflows.
- [Operations handbook](docs/OPERATIONS.md) — every helper, configuration and
  safe operating procedure.
- [Troubleshooting](docs/TROUBLESHOOTING.md) — symptom-led diagnosis and guarded
  recovery.
- [Development guide](docs/DEVELOPMENT.md) — architecture, security, testing,
  language, CI and release conventions.
- [Distribution portability](docs/PORTABILITY.md) — support tiers, Arch/Ubuntu
  adapters, efficient container tests and packaging gates.
- [Real desktop release gates](docs/DESKTOP_GATES.md) — privacy-safe target
  reports and the clean installation checklist.
- [Security policy](SECURITY.md) — private reporting, supported versions and
  explicit trust boundaries.

Contributions are welcome. Run `make check` before opening a pull request; both
Functional checks and Super-Linter are intended to be required checks.

## Community and support

- [PDrive — Proton Drive at home on Linux](https://forum.rclone.org/t/pdrive-proton-drive-at-home-on-linux/54205)
  — project introduction, screenshots and broader rclone-community feedback.
- [Proton Drive x rclone](https://forum.rclone.org/t/proton-drive-x-rclone/53609/24)
  — Proton backend coordination and OSS Singularity's stewardship offer.
- [GitHub Issues](https://github.com/oss-singularity/proton-drive-linux/issues)
  — PDrive-specific support, bug reports and feature requests.

Please use GitHub Issues for PDrive support. The rclone forum threads are for
broader community discussion and upstream coordination rather than third-party
support.

## Limitations

- Proton and rclone backend behavior can change independently of this project.
- There is no per-folder “always available offline” feature.
- A same-user process can stop a same-user FUSE mount.
- Keep independent backups and verify important remote writes.

## License

Licensed under GPL-3.0-or-later. See [LICENSE](LICENSE).

## References

- [rclone Proton Drive backend](https://rclone.org/protondrive/)
- [rclone mount and VFS cache](https://rclone.org/commands/rclone_mount/)
- [Official Proton Drive CLI](https://proton.me/support/drive-cli)

## A personal note from Claudiu & Codex

> We — Claudiu & Codex — loved turning a stubborn real-world mount into
> something observable, careful and genuinely pleasant to use. Made with love
> for people on this beautiful world who want Linux to feel like home. 💜
