# Distribution portability

PDrive is moving from one proven Linux Mint integration toward one portable
Linux codebase. The project does not maintain per-distribution feature branches
or mechanically backport commits between them. Distribution differences belong
in small reviewed adapters, package recipes and tests beside the shared source.

Linux Mint 22.x Cinnamon remains the reference and currently supported desktop.
Arch Linux and Ubuntu are the first portability targets. Their presence in an
adapter or container test is not yet a support claim; each target is promoted
only after its complete release gate has passed.

## Portability envelope

The initial cross-distribution product still expects:

- an x86-64 Linux desktop, because the pinned PDrive rclone build currently has
  only an x86-64 asset;
- systemd user services tied to a normal graphical login;
- FUSE 3 and the owner-only `/pdrive` mountpoint;
- GTK 3, PyGObject and an Ayatana AppIndicator or GTK tray fallback;
- a Secret Service-compatible login keyring, currently tested with GNOME
  Keyring;
- Polkit for the optional privileged package and mountpoint preparation steps;
- standard XDG desktop integration and a graphical file manager.

A distribution outside this envelope may still run the lower-level helpers,
but it is not a supported PDrive desktop until its alternative lifecycle,
credential and UI behavior has been designed and tested.

## Target status

| Distribution                | Current status       | Promotion work still required                                                                                            |
| --------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Linux Mint 22.x Cinnamon    | Reference, supported | Keep the full local and online suite green and retain live Cinnamon/Nemo release testing.                                |
| Ubuntu 24.04 LTS            | Initial target       | Complete package layout, clean-system installation, GNOME/keyring/tray testing and release packaging.                    |
| Arch Linux                  | Package candidate    | Keep smoke and native-package gates green; complete clean-system installation and Fabi's live desktop validation.        |
| Debian                      | Prepared next        | Reuse the Debian-family adapter, then validate supported desktop and package versions explicitly.                        |
| MX Linux                    | Planned              | Decide and test the supported systemd mode; the default non-systemd experience is outside today's lifecycle contract.    |
| Fedora                      | Planned              | Add an RPM-family package adapter, spec file and SELinux-aware desktop tests.                                            |
| CentOS Stream / RHEL family | Planned              | Establish available GTK, AppIndicator and Python versions before defining a supported release.                           |
| Univention UCS              | Future request       | Treat as a separate Debian-derived, server-oriented target; first define the intended desktop and user-session use case. |

## One source tree, small adapters

`bin/pdrive-platform` is the read-only distribution adapter. It parses
`os-release` as data and maps exact distribution identifiers to reviewed package
names and fixed package-manager invocations. The setup wizard and diagnostics
consume that adapter instead of carrying separate package maps. Unsupported
systems receive manual, non-mutating guidance rather than a guessed privileged
command.

Runtime behavior remains shared. Platform adapters must not duplicate mount,
authentication, cache, recovery, bandwidth or state logic. Package recipes may
select filesystem destinations, but they must install the same tested helpers
and preserve the stable application ID and `/pdrive` contract.

## Efficient test ladder

The test ladder deliberately spends resources in proportion to the signal it
provides:

1. Every change runs fast adapter fixtures, syntax, security and behavior tests
   on the Ubuntu-based GitHub runner already used by the project.
2. Runtime-relevant pull requests and `main` changes run one focused Arch Linux
   smoke test. The repository is mounted read-only into one disposable
   container; no VM, persistent container or volume is created.
3. A weekly Arch run detects rolling-distribution package or ABI drift even
   when the repository has not changed.
4. Before a distribution is called supported, a clean desktop installation and
   the manual release checklist validate login-keyring unlock, Polkit, tray,
   file-manager opening, user-systemd startup, writable FUSE mount and safe
   uninstall. The procedure and privacy-safe report format live in
   [Real desktop release gates](DESKTOP_GATES.md). Automated tests never use real
   Proton credentials.

Run the shared adapter tests locally with:

```bash
make check-platforms
```

Run the Arch smoke test with an image already present in rootless Podman:

```bash
make check-arch
```

Build, inspect with `namcap`, install and probe the native Arch package inside
one disposable container with:

```bash
make check-arch-package
```

The resulting local candidate is written below ignored `dist/arch/`; neither
command publishes an image, stable package, tag or release. On pull requests
and explicit workflow dispatches, the same Arch compatibility job reuses its
already pulled image, runs the native package gate and uploads the compressed
package for seven days as `proton-drive-linux-arch-<commit>`. This ephemeral,
commit-bound test candidate exists only for the clean-desktop gate; it is not a
stable distribution package.

The runner refuses to download an image implicitly. To opt into a current image
download, run:

```bash
tests/run-distro-smoke.sh --pull arch
```

`tests/run-distro-smoke.sh all` can exercise both Ubuntu 24.04 and Arch Linux
sequentially in the same runtime when a release candidate needs the extra
clean-image check. The exact image identifier is printed after every run.

## Cost and GitHub release gates

The repository is public, so standard GitHub-hosted runners are
[free and unlimited for public repositories](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
The compatibility workflow uses one standard Ubuntu runner and runs the Arch
containers sequentially inside that job so the base image is pulled only once.
It creates no persistent cache. Scheduled and `main` runs upload nothing; pull
requests and explicit dispatches retain only the already-compressed package
candidate for seven days with artifact recompression disabled. It does not use
larger paid runners or a self-hosted machine.

GitHub Environments are deployment controls, not extra test machines. They are
therefore intentionally deferred until packages are actually published. At
that point, separate `ubuntu-package` and `arch-package` environments can gate
signing and publication after all checks pass, restrict release branches and
require a human approval before environment secrets become available. GitHub
documents environments and required reviewers as
[available to public repositories on current plans](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).
Normal pull-request tests remain environment-free and never receive publishing
credentials.

## Packaging sequence

Distribution packages follow the portability work rather than leading it:

1. The relocatable static installer preserves the existing copy-based
   `~/.local` layout and also stages native `/usr` package contents.
2. The system layout keeps immutable project code under
   `/usr/lib/proton-drive-linux`, exposes public commands through `/usr/bin` and
   installs desktop assets, documentation and systemd user units without
   executing maintainer code as root.
3. The first checksum-pinned Arch PKGBUILD template and disposable package gate
   consume that same staged tree. Ubuntu/Debian packaging follows it.
4. Test install, upgrade, rollback and uninstall while retaining configuration,
   credentials, state and every VFS cache namespace.
5. Publish a distribution package only after the corresponding clean-system
   and desktop gates pass.

This order avoids creating superficially valid packages whose systemd units
still point at user-local paths or whose dependency list cannot start the GTK
application.
