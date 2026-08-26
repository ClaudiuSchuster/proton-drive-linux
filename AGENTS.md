# Repository Instructions

These instructions apply to the entire repository. Keep them concise and
project-specific; CI remains the authority for mechanical formatting rules.

## Product Contract

- Build a dependable, approachable Proton Drive integration for Linux Mint
  Cinnamon and Nemo. Preserve advanced control without making routine use feel
  like system administration.
- Treat rclone's Proton Drive backend as experimental. Never imply that this
  project is an official Proton product or that data safety is guaranteed.
- `/pdrive` is the canonical owner-only FUSE mount. The normal deployment is a
  user systemd service unlocked by the graphical login and GNOME Keyring.
- Files may be 100 GiB or larger. An idle interval, unchanged queue, low network
  traffic, or a long-running transfer is not by itself evidence of a stall.
- Preserve local VFS data across ordinary service recovery. Never discard dirty
  cache files, interrupt active transfers, or restart the mount merely to make
  a status display look fresh.

## Language and UX

- Write code, identifiers, comments, commit messages, public documentation, and
  development metadata in English.
- PDrive Control Center defaults to English and supports complete English and
  German UI translations. Any new visible UI string must be added to both
  languages in the same change. Do not introduce German identifiers or
  functional constants.
- Existing German terminal-helper output is legacy behavior. Do not expand that
  inconsistency casually; any CLI localization should be a deliberate,
  complete change.
- Keep the GTK interface responsive, keyboard accessible, and useful at its
  minimum width. On launch, fit the window height to its content when the screen
  allows it; show a scrollbar only when the available display height requires
  one.
- Preserve tray behavior: left click opens the main window, right click opens
  the control menu. Hidden-window polling follows the user's preference; the
  independent watchdog remains responsible for background health monitoring.
- Prefer explanation at the point of confusion. Overview cards should lead to
  the relevant detail section, advertise clickability through pointer, hover,
  pressed and keyboard-focus states, and distinguish protected pending uploads
  from clean retained cache copies.
- Distinguish Proton account capacity from local cache-filesystem capacity.
  Remote quota reads are low-frequency; never tie them to the configurable live poll.
  Keep graph sources explicit: rclone RC for uploads and process-owned TCP
  receive counters for VFS download traffic, with API overhead disclosed.
- Keep the compact overview useful without hiding diagnostics: summarize
  service uptime and restart count in “What’s happening”, while retaining the
  full systemd, mount, and watchdog details on History.
- Preserve rclone bandwidth semantics: `0`/`off` means unlimited. A UI
  near-pause must use the documented low nonzero rate and must never be
  presented as a native pause.
- Use “PDrive” for this project and local tooling; use “Proton Drive” or
  “Proton cloud” for Proton’s service and web destination.
- An issue counter must lead to reviewable evidence before acknowledgment:
  timestamp, severity, PDrive-specific category, sanitized context, affected
  path when safe, and a useful next step. Never acknowledge merely by opening
  the detail view.
- Keep Apply and Save actions insensitive until the user has made an effective
  change, and disable them again when every value returns to its initial state.
- Keep the Operations handbook's Control Center settings reference complete:
  every user-facing setting or guarded action must state its access path,
  accepted values and default, persistence, activation timing and safety impact.
- Keep the public README user-facing. Do not expose demo implementation notes,
  private deployment details, session instructions, or maintainer-only prose.
  Screenshots may use privacy-safe demo data, but the README need not announce
  that fact.
- Keep local artwork used by the native documentation viewer available in every
  installation and package. Render it locally without fetching remote badges or
  introducing a browser engine.

## Architecture Boundaries

- `bin/pdrive-state` is the machine-readable aggregation layer for the GUI.
  Extend its versioned JSON schema instead of duplicating systemd, rclone RC,
  queue, cache, or log parsing in `bin/pdrive-ui`.
- The GUI should invoke the existing narrowly scoped helpers for mutations.
  Do not reimplement bandwidth, transfer-slot, cache-age, refresh, recovery, or
  authentication rules in GTK callbacks.
- Keep no-argument and `--help` invocations action-free. Mutating helpers must
  require an explicit action option and retain their validation and confirmation
  gates.
- Parse configuration files as data; never source them as shell code. Validate
  every persisted value against the helper's intentionally narrow grammar.
- Keep the rclone RC endpoint on the owner-only mode-0700 Unix socket. Never
  expose it on TCP, weaken its permissions, or place secrets in URLs.
- Proton credentials, configuration passwords, and 2FA codes must never appear
  in process arguments, environment variables, logs, fixtures, screenshots, or
  Git. Continue using anonymous pipes, encrypted rclone configuration, GNOME
  Keyring, restrictive umasks, and atomic file replacement.
- The exclusive Proton metadata cache is a performance feature with an explicit
  consistency tradeoff. Retain the guarded refresh path and document that other
  Proton clients must not write concurrently while it is enabled.
- Health reporting must distinguish no work from failed work. Automatic recovery
  requires corroborating queue/error evidence, repeated confirmations, and the
  configured cooldown; it must not restart a healthy idle mount.
- A stall inside the guarded draft-recovery namespace may receive at most one
  automatic restart per exact cache generation. Require prior matching transfer
  progress, a newer concrete path-specific error, healthy connectivity, two
  separated zero-activity probes and full post-restart PID/flag/namespace/queue
  validation. Near-pause bandwidth and a process change always suppress it.
- Avoid new runtime dependencies when Python's standard library, GTK 3, and the
  installed GI stack are sufficient. Do not add WebKit merely to render local
  documentation.

## Installation and Packaging

- `install.sh` is the stable copy-based user-local installer. Re-running it may
  update installed project files, but must preserve credentials, configuration,
  cache, state, and user data.
- Do not change the public installer to create repository symlinks. Direct
  symlinks are suitable only for an explicitly managed development machine whose
  operator wants the checkout to become the live version.
- Desktop entries and icons should be installed as regular files so Cinnamon's
  menu and icon caches behave predictably.
- The intended public update path is versioned Debian packaging through APT and
  Linux Mint's Update Manager or Software Manager. Until that channel actually
  exists, describe Git pull plus `install.sh` accurately and do not claim store
  availability.
- Privileged setup may execute only fixed, auditable system programs through
  Polkit. Never execute a user-writable project script as root.
- Keep installation, uninstallation, and the first-run wizard idempotent where
  practical. Existing configured systems must bypass first-run account setup.

## Source Map

- `bin/pdrive-ui`: GTK 3 control center, setup wizard, translations, tray, and
  in-app documentation viewer.
- `bin/pdrive-state`: side-effect-free JSON snapshot consumed by the GUI.
- `bin/pdrive-*`: guarded user-facing operations.
- `libexec/rclone-proton-mount`: authoritative mount arguments and runtime
  configuration parsing.
- `libexec/setup-rclone-proton`: bounded initial rclone/Proton configuration.
- `libexec/reauth-rclone-proton`: isolated transactional credential replacement.
- `systemd/user`: mount, watchdog, and updater lifecycle.
- `tests`: action-free help checks, fixtures, setup safety, state schema, and GTK
  behavior.
- `README.md`: product overview and common installation/use.
- `docs/OPERATIONS.md`: complete operational reference.
- `docs/TROUBLESHOOTING.md`: symptom-led diagnosis and recovery.

## Verification

- Run `make check` after every behavior or documentation change. It includes
  shell syntax and ShellCheck, Python compilation, action-free help tests,
  fixtures, setup tests, version consistency, desktop validation when available,
  and GTK widget checks.
- Run `git diff --check` before committing.
- For UI changes, exercise both languages, the minimum supported width, content
  fitting on a normal desktop, tray actions, and both zero-activity and active
  transfer states. Use fixtures or demo mode rather than a real cloud mutation.
- Capture Cinnamon product images through one X11 root screenshot followed by
  an exact crop. Do not automate repeated `ScreenshotArea` D-Bus calls; that
  path has caused reproducible Cinnamon crashes. Keep the active-window
  highlight visible in the main product shot.
- For state-schema changes, update fixtures and UI consumers together. Preserve
  backwards-compatible defaults when a field can be absent from an older
  snapshot.
- For helper changes, verify that no-argument and `--help` paths remain
  action-free and add a regression test for each fixed failure mode.
- GitHub Actions must pass both Functional checks and Super-Linter. Do not hide
  a real warning merely to make CI green; suppress only understood environment
  noise at its source.
- Begin every versioned YAML file with the explicit `---` document marker. The
  portable repository suite enforces this so yamllint output remains warning-free.
- Keep the Checks workflow on pull requests plus pushes to `main`. Enabling it
  for every branch push duplicates both required jobs for same-repository pull
  requests without adding a distinct validation boundary.
- Never run the state-writing watchdog against a live deployment from a sandbox
  that cannot access the user bus or owner-only RC socket. Such failures are
  tooling limitations, not evidence that the service is down.

## Live-System Safety

- Inspect before mutating. A source-code change, symlink update, or
  `systemctl --user daemon-reload` does not require restarting a healthy mount.
- Before any requested restart, inspect the queue, active transfers, dirty cache
  files, mount state, and current PID. Validate the new PID, writable mount, RC
  socket, and queue afterward.
- Do not use real credentials or a real Proton account in automated tests.
- Do not delete caches, backups, remote files, or failed upload artifacts unless
  the exact targets and recovery consequences are understood and the user has
  explicitly authorized it.
- Sandbox failures such as inaccessible user D-Bus, Unix sockets, FUSE options,
  or DNS must be rechecked in the real user-session context before diagnosis.

## Versioning and Git

- The canonical public repository is
  `https://github.com/oss-singularity/proton-drive-linux`. Keep project badges,
  clone commands, security-reporting routes, issue templates, release links,
  documentation fallbacks and sibling-project links on the `oss-singularity`
  organization. Personal author, credit, Code Owner and sponsorship links may
  continue to target their individual GitHub profiles.
- Preserve the installed application ID `io.github.claudiuschuster.PDriveControl`
  across the repository transfer. It is a stable desktop, D-Bus, autostart and
  preference identity, not a repository URL; changing it requires a separately
  designed end-user migration.
- `VERSION` is the project SemVer source. It must exactly match `VERSION` in
  `bin/pdrive-ui` and `TOOL_VERSION` in `bin/pdrive-state`.
- The desktop file's `Version=1.0` is the Desktop Entry specification version,
  not the application version; do not synchronize it with project SemVer.
- Use annotated immutable tags named `vX.Y.Z` on the exact tested release commit.
  Publishing such a tag and publishing its matching GitHub Release are one
  inseparable release operation: every pushed SemVer tag must receive a
  non-draft GitHub Release with concise user-facing notes in the same workflow.
  Mark the highest stable version as Latest and mark an actual prerelease
  accordingly. If the GitHub Release is not ready to publish, do not push the
  tag. Perform both only after local checks and the commit's GitHub Actions run
  are green.
- Release notes must summarize user-visible changes since the previous release,
  state the supported upgrade path and link the full comparison. Do not expose
  private deployment details, maintainer-session notes or credentials. In
  particular, never mention a maintainer's live installation, repository
  symlinks, host-specific state, current commit deployment, service PIDs, local
  paths, or private operating workflow. Keep those facts only in the private
  work log or machine-specific operations documentation.
- Name GitHub Releases `vX.Y.Z — PDrive Control Center` so the version remains
  visible in GitHub's narrow release list. Keep the matching Git tag exactly
  `vX.Y.Z`.
- Do not move an existing release tag, force-push, rewrite shared history, or
  publish credentials and machine-specific paths.
- Keep commits focused and use short imperative English subjects. Preserve
  unrelated working-tree changes and never commit private operating notes from
  outside this repository.
- The repository accepts squash merges only. Keep pull-request commits focused,
  then merge through GitHub's squash path rather than creating a merge commit.
- Update this file when verified packaging, migration, rollback, or store-review
  behavior establishes a new repository-wide invariant. Do not encode an
  untested publishing assumption as policy.

## Code Review Rules

- Flag any route that can leak credentials or 2FA, expose the RC API over the
  network, weaken owner-only permissions, or execute mutable code with elevated
  privileges.
- Flag watchdog logic that equates inactivity with failure or can restart during
  a valid large upload.
- Flag cache cleanup that can remove dirty or uploading files.
- Flag GUI mutations that bypass existing guarded helpers or block the GTK main
  loop with network, systemd, or setup work.
- Flag public claims about official Proton support, Mint store availability, or
  automatic project updates that the repository does not yet provide.
