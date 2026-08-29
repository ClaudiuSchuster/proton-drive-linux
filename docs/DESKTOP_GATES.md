# Real desktop release gates

Container checks prove dependency resolution and headless GTK behavior. They do
not prove that a package works in a real graphical login. Every distribution
must therefore pass the gates below on a clean target desktop before PDrive
calls it supported or publishes a distribution package as stable.

The gate never substitutes activity on the maintainer's live mount for target
platform evidence. Automated checks do not log in to Proton, call its API,
create a remote file, restart a service or write into `/pdrive`.

## Privacy-safe automated report

Install the exact release candidate, open a terminal inside the ordinary
graphical login and run:

```bash
pdrive-desktop-gate --markdown --strict > pdrive-desktop-preflight.md
```

The report checks:

- the reviewed distribution adapter, architecture and installed package map;
- a real X11 or Wayland session, its D-Bus session bus and systemd user manager;
- GTK 3, PyGObject, Cairo, the tray library and `/dev/fuse`;
- installed helpers, desktop entry, icon, systemd user units and owner-only
  `/pdrive` directory;
- the Control Center's action-free `--check` path.

The versioned JSON form is available for tooling:

```bash
pdrive-desktop-gate --json --strict > pdrive-desktop-preflight.json
```

The generated report intentionally excludes hostname, user name, home path,
display address, process IDs, local or remote file names, configuration values,
logs and credentials. Review the small report before sharing it anyway. A
failed strict run still writes the report and returns a nonzero status.

## Clean installation gate

Use a clean user account or a disposable test machine. Record the release
version and package checksum outside the report, then require all of the
following:

- [ ] Installation finishes without a distribution-specific manual repair.
- [ ] The automated preflight report says `PASS`.
- [ ] The desktop menu shows “PDrive Control Center” with its normal icon.
- [ ] Starting from the menu creates one application instance and a readable
      main window.
- [ ] Overview, Transfers and History fit at the supported minimum width;
      content scrolls only when the available display height requires it.
- [ ] Keyboard navigation reaches every control and visible text is complete in
      both English and German.
- [ ] Closing, reopening and tray hide/show follow the saved preference. Left
      click opens the window and right click opens the control menu.
- [ ] The documentation viewer renders its packaged local text and artwork
      without a network fetch.

Use `pdrive-ui --demo` when synthetic transfer states are helpful. Demo mode is
safe for visual inspection but cannot prove keyring, mount, login or tray
lifecycle behavior.

## Configured desktop gate

The tester must explicitly authorize using a Proton test account or their own
account. Never reuse a maintainer's credentials and never include account data
in the report. Complete the normal setup wizard, then run:

```bash
pdrive-desktop-gate --configured --markdown --strict \
  > pdrive-desktop-configured.md
```

In addition to the preflight gates, this proves only local facts: an encrypted
configuration exists, its keyring entry is available, the mount service is
active, `/pdrive` is an active writable FUSE mount and `pdrive-state` can read a
versioned snapshot. It performs no Proton API request.

Manually confirm:

- [ ] `/pdrive` opens through the desktop's file manager and remains owner-only.
- [ ] The Control Center distinguishes remote quota from local cache capacity.
- [ ] With explicit permission, one small disposable upload reaches remote
      success and one download completes; UI state agrees with the actual result.
- [ ] An idle interval does not produce a false stall or automatic restart.
- [ ] A fresh graphical logout/login unlocks the keyring, starts the enabled
      systemd user units and restores the tray preference without a login loop.
- [ ] Re-running the installer preserves configuration, credentials, state and
      cache and does not restart a healthy active mount.

Do not exercise rollback or uninstall while a queue entry, transfer or Dirty
VFS cache file exists. Those destructive lifecycle gates belong on a disposable
account or machine and must verify retained configuration and cache separately.

## Arch Linux promotion record

For a pull request or manually dispatched compatibility run, download the
`proton-drive-linux-arch-<commit>` Actions artifact and record both the workflow
commit and the package SHA-256 before installation. The artifact expires after
seven days and is a test candidate, not a stable package publication.

For the first Arch release, retain this evidence in the release issue or pull
request:

```text
Arch installation:
- workflow commit:
- release candidate version:
- package or bundle SHA-256:
- desktop environment and session type:
- automated preflight report: PASS / FAIL
- automated configured report: PASS / FAIL
- clean installation checklist: PASS / FAIL
- configured desktop checklist: PASS / FAIL
- logout/login lifecycle: PASS / FAIL
- tester notes (no private paths, names, logs or credentials):
```

Promotion requires green repository checks, the rolling Arch container job and
one complete clean Arch desktop record. A report from an already customized
machine is useful additional evidence but does not replace the clean install.
Ubuntu follows the same process with its own package and clean Ubuntu desktop.

The first clean Arch record was completed for pull request
[`#66`](https://github.com/oss-singularity/proton-drive-linux/pull/66): the
commit-bound `0.8.0-1` package was installed on a fresh Arch Cinnamon/X11
desktop, passed all 15 automated preflight gates, tray and Nemo interaction,
English and German UI checks, logout/login lifecycle and package integrity.
The gate exposed and closed a 1280x800 work-area overflow before release. The
exact reviewed package SHA-256 is recorded in the pull request and matching
release notes. Configured Proton-account and transfer review remains required
before Arch is described as generally supported.
