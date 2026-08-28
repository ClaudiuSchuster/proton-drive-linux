# Development guide

This guide is for contributors working on proton-drive-linux itself. The
[README](../README.md) stays focused on the product and installation.
[Quick start](QUICK_START.md) and [Everyday use](EVERYDAY_USE.md) serve normal
users; [Operations](OPERATIONS.md) and [Troubleshooting](TROUBLESHOOTING.md)
remain the authoritative maintenance and recovery handbooks.

## Product boundaries

PDrive Control Center is a dedicated local Proton Drive client experience, not
a generic rclone GUI. It observes and controls one existing owner-only rclone
mount at `/pdrive`. Routine actions should feel approachable, while dangerous
recovery paths remain explicit and conservative.

rclone's Proton Drive backend is beta. Files may exceed 100 GiB, uploads may run
for days and connectivity may disappear temporarily. No-work and slow-work
states must not be diagnosed as failures without corroborating evidence. Never
discard pending VFS data or restart an active transfer to refresh the UI.

## Architecture

```text
Cinnamon session
  -> GNOME Keyring
  -> user systemd
  -> rclone-proton-drive.service
  -> one rclone mount
  -> /pdrive

PDrive Control Center
  -> pdrive-state
  -> owner-only rclone RC Unix socket
  -> narrowly scoped pdrive-* helpers for mutations
```

`bin/pdrive-state` is the side-effect-free JSON aggregation layer. GTK code must
consume its versioned schema instead of independently parsing systemd, queue,
cache or log state. Mutations delegate to existing guarded helpers.

Live upload speed comes from rclone `core/stats`. Mount reads are not exposed as
a separate RC rate, so download traffic is derived from Linux TCP payload
counters owned by the exact systemd service PID. This includes small Proton API
responses but excludes browsers and unrelated rclone mounts. Proton capacity
may require a backend request and is therefore sampled only at startup, every
15 minutes and on explicit refresh.

Bandwidth mutation is backend-specific by design. `pdrive-bwlimit` calls the
Proton backend's `data-bandwidth` runtime command; the backend wraps shared
aggregate upload and download file readers while metadata HTTP requests bypass
the limit. Never replace this with rclone's global `core/bwlimit` on the live
mount. Saved limits are applied only after mount startup so backend option
values cannot alter the VFS cache fingerprint and select a different Dirty
queue namespace.

## Security model

- The rclone configuration is encrypted with a random password stored in the
  login-unlocked GNOME Keyring.
- Credentials and 2FA codes travel through anonymous stdin pipes. They must
  never enter arguments, environment variables, logs, fixtures or Git.
- The RC endpoint is a mode-0700 Unix socket and must never be exposed on TCP.
- `/pdrive` is owner-only. No project script is executed as root; Polkit setup
  may invoke only fixed, auditable system programs.
- Issue evidence is bounded and sanitized before entering the UI snapshot.
  URLs, share identifiers and credential-shaped values are redacted.
- No automated test may use a real Proton account or real credentials.

See [AGENTS.md](../AGENTS.md) for the complete repository invariants and review
rules.

## Repository map

```text
bin/             GTK UI, state adapter and user-facing helpers
libexec/         mount, unmount, setup and updater implementations
systemd/user/    mount, watchdog and updater lifecycle
share/           desktop launcher and scalable application icon
docs/            user, operator and developer documentation
tests/           fixtures, safety checks and GTK behavior tests
install.sh       idempotent copy-based user-local installer
uninstall.sh     guarded removal of repository-managed files
```

## Local development

The public installer copies versioned files into user-local destinations:

```bash
./install.sh
```

Do not change that contract to repository symlinks. A maintainer may explicitly
replace managed executables with absolute links into a trusted checkout for a
live development machine, but desktop entries and icons should remain regular
files so Cinnamon's caches behave predictably.

Run the full local suite before every commit:

```bash
make verify
```

### Pinned rclone dependency

The installed binary comes from the public
[`oss-singularity/rclone`](https://github.com/oss-singularity/rclone) release
`pdrive-v1.76.0-beta.10204.2`. Its branch pins the exact
[`oss-singularity/Proton-API-Bridge`](https://github.com/oss-singularity/Proton-API-Bridge)
commit `c059d7573afb` used to build the asset. The bridge worker-drain correction
is proposed upstream in
[Proton-API-Bridge PR #8](https://github.com/rclone/Proton-API-Bridge/pull/8);
the dependent failed-block retry remains separately tracked in
[PDrive issue #42](https://github.com/oss-singularity/proton-drive-linux/issues/42)
until it can be proposed upstream as one focused follow-up commit.
The independent Proton file-data limiter, its reproduction measurements and the
public prototype are tracked in
[rclone issue #9832](https://github.com/rclone/rclone/issues/9832). Keep these
upstream efforts separate: one fixes leaked upload-worker slots after errors;
the other limits only bulk file readers so API metadata remains responsive.
The Linux x86-64 asset is statically linked and its checksum is embedded in
`pdrive-prerequisites` and published beside the release.

Treat the release branch, annotated tag, source replace and checksum as one
review unit. Updating only the executable or only the embedded digest is not a
valid dependency upgrade. The binary intentionally retains its exact upstream
rclone version string so VFS cache identity and minimum-version guards remain
stable; detect the PDrive extension through `backend help protondrive` and the
`data-bandwidth` command.

`make help` lists action-free developer entry points. `make check-units` runs
the focused systemd invariants and static verification, while
`make check-display` exercises both GTK suites on the current desktop. The
portable `make check` remains the CI entry point and automatically uses Xvfb
when it is installed.

For UI changes, also run the real-display widget suite where a disposable
display is unavailable:

```bash
./tests/test-ui-widgets.sh --use-display
```

Exercise both languages, minimum width, zero and active transfer fixtures,
Preferences dirty-state behavior, issue review and content-height fitting. Use
an implausible stale rclone speed/ETA pair beside zero process-owned TCP traffic
as a regression fixture; the active row must not present it as live activity.
Never run the state-writing watchdog against a live deployment from a sandbox
that cannot access its user bus, FUSE mount or RC socket.

For Cinnamon product screenshots, activate the disposable demo window, take one
X11 root capture and crop the exact window or popover region. Do not automate
repeated Cinnamon `ScreenshotArea` D-Bus calls; that path has caused reproducible
shell crashes. Include the active-window highlight in the main product image.
Choose a stable initial tab without synthetic pointer input through
`pdrive-ui --demo --demo-page overview|transfers|history`.

## UI and language

Code, identifiers, public documentation and development metadata are English.
The UI defaults to English and every visible string must receive a complete
German translation in the same change. Keep GTK 3 and the installed GI stack;
avoid a browser engine or another runtime dependency for local documentation.
Terminal helper usage, diagnostics and errors are English-first. Desktop
notifications default to English but may follow the saved German UI preference.
Legacy German watchdog keys remain input-compatible state, not a public-output
pattern for new code.

The in-app Markdown viewer intentionally implements only the project's bounded
subset. Local packaged artwork is rendered natively. Remote badges are not
fetched. Save and Apply actions remain disabled until an effective value has
changed and disable again when the original values are restored.

## CI and release process

`make check` covers syntax, ShellCheck, action-free help behavior, setup safety,
transactional reauthentication, terminal-authentication retry suppression,
systemd semantics, state fixtures, version consistency, desktop validation and
GTK checks when the display stack is available. GitHub Actions also runs
Super-Linter for Bash, Python, Markdown, YAML, action security and secret
scanning. Pull requests receive one required Functional-check and Super-Linter
pair; pushes are limited to `main`, where the resulting merge commit is checked
once more. Do not broaden the push trigger to feature branches, because
same-repository pull requests would run both jobs twice for the same source
commit.

`VERSION`, `bin/pdrive-ui::VERSION` and `bin/pdrive-state::TOOL_VERSION` must
match exactly. Releases use immutable annotated `vX.Y.Z` tags on a commit whose
Functional checks and Super-Linter jobs are green. A pushed SemVer tag and its
matching non-draft GitHub Release are one operation; if release notes are not
ready, the tag is not pushed. The highest stable release is marked Latest and
the release is titled `vX.Y.Z — PDrive Control Center`. Notes summarize
user-visible changes, the upgrade path and the full comparison. Do not claim
Linux Mint Software Manager or APT availability until that publishing channel
exists.

## Contributing

Keep commits focused with short imperative English subjects. Explain observable
behavior changes and add regression coverage for every fixed failure mode.
Changes involving credentials, cache eviction, watchdog restarts, RC exposure or
privileged setup deserve explicit security review.
Use the [security policy](../SECURITY.md) for private vulnerability reports and
the repository issue templates for ordinary reproducible defects and feature
ideas.
