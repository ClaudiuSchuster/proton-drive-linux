# Troubleshooting

Start locally. Repeated Proton login tests and blind service restarts can make a
temporary condition worse.

```bash
pdrive-watch
pdrive-doctor
systemctl --user status rclone-proton-drive.service
journalctl --user -u rclone-proton-drive.service -n 100 --no-pager
```

Only add `pdrive-doctor --online` when no HTTP 429 backoff is active and a real
API test is necessary.

## First-run wizard cannot continue

The readiness page identifies whether commands, the current rclone backend or
`/pdrive` still need attention. On Linux Mint, Debian, Ubuntu and Arch Linux,
**Install and prepare automatically** uses the reviewed platform adapter and
Polkit and may show the normal administrator password prompt. If package
installation is unavailable or fails, expand
**Manual setup for advanced users**, run the displayed commands in a terminal,
then select **Check again**.

A failed Proton login does not install `rclone.conf`; correct the problem and
retry with a fresh six-digit 2FA code. After an HTTP 429 response, do not submit
codes repeatedly: wait for Proton's complete backoff first. If the encrypted
config exists but service activation failed after login, open the dashboard and
run `pdrive-doctor`; the valid account configuration is retained.

## Safe evidence collection

Prefer local, redacted evidence:

```bash
pdrive-doctor
pdrive-watch
systemctl --user status rclone-proton-drive.service --no-pager
journalctl --user -u rclone-proton-drive.service -b --no-pager
rclone config redacted proton
```

Never publish `rclone config show`, a decrypted `rclone.conf`, Keyring output,
passwords, TOTP seeds or `client_*` session fields. Avoid permanently switching
the mount to DEBUG: verbose output can expose more metadata and can accompany
extra API activity. Reproduce with the normal INFO log first and redact private
paths from excerpts. rclone itself warns that redaction may not be perfect, so
double-check even `config redacted` before posting it.

## Mount missing after login

Check the exact chain:

```bash
systemctl --user is-enabled rclone-proton-drive.service
systemctl --user show rclone-proton-drive.service \
  -p ActiveState -p SubState -p MainPID -p Result -p ExecMainStatus -p NRestarts
findmnt -M /pdrive
timeout 5 secret-tool lookup service rclone account proton-drive >/dev/null
```

Expected: enabled, active/running, a non-zero PID, `Result=success`, a
`fuse.rclone` mount and a successful Keyring lookup. The service starts after
the graphical login, not at the display-manager screen, because the login
Keyring must be unlocked first.

If `/pdrive` was deleted or has the wrong owner:

```bash
sudo install -d -m 0700 -o "$(id -un)" -g "$(id -gn)" /pdrive
systemctl --user start rclone-proton-drive.service
```

The wrapper refuses symlinks or foreign ownership rather than mounting over an
unexpected path.

## `fusermount3: entry ... not found in /etc/mtab`

This commonly means an unmount was requested when no matching mount existed. It
is not itself proof that FUSE is broken. The shipped unmount helper first checks
`mountpoint` and `findmnt` and only calls `fusermount3` for a confirmed FUSE or
rclone filesystem.

## `Transport endpoint is not connected`

The FUSE process disappeared while the kernel mount entry remained. Confirm no
important queue is recoverable only from the running process, then:

```bash
fusermount3 -uz /pdrive
systemctl --user start rclone-proton-drive.service
```

Do not delete `~/.cache/rclone` as a generic fix. It may hold the only complete
local copy of writes that have not reached Proton.

## FUSE reports `Operation not permitted`

Check the helper, device and optional group first:

```bash
ls -l /usr/bin/fusermount3
ls -l /dev/fuse
getent group fuse
```

Do not add generic systemd hardening without testing the actual FUSE and
Keyring path. `NoNewPrivileges=true`, `PrivateMounts=true`,
`PrivateDevices=true` or a restrictive `ProtectHome=true` can block
`fusermount3`, the mount namespace, `/dev/fuse`, GNOME Keyring or the user's
configuration/cache. The shipped mount unit deliberately relies on `UMask=0077`
instead of these incompatible restrictions.

## Service remains `activating (start)`

This can be valid during a large persisted VFS-cache inventory or while waiting
for the Keyring. Inspect process age, cache, queue and log movement with
`pdrive-watch`. The unit deliberately uses an unlimited start timeout so systemd
does not repeatedly kill a legitimate Proton backoff or a long startup scan.

If no queue exists and the Keyring is locked, log out and back into Cinnamon or
repair the login-Keyring/PAM integration. Do not add automatic password files as
a shortcut.

## Keyring remains unavailable after login

```bash
dpkg-query -W gnome-keyring libpam-gnome-keyring libsecret-tools
systemctl --user status gnome-keyring-daemon.service
timeout 5 secret-tool lookup service rclone account proton-drive >/dev/null
echo $?
```

Exit status zero is expected; keep lookup output redirected so the secret is
never printed. If the Linux login password changed while the login Keyring kept
its old password, Cinnamon may no longer unlock it automatically. Repair the
login Keyring with the desktop's password/keyring application or bind it to the
current login password.

Creating a new empty Keyring destroys access to the old rclone configuration
password. Restore encrypted `rclone.conf` and its matching Keyring item as a
pair, or deliberately create a new encrypted configuration. Do not replace the
Keyring item while pending Dirty cache data depends on the old remote config.

## No traffic for several minutes

No traffic is normal when:

- the live VFS queue is empty;
- rclone is listing or decrypting many small metadata objects;
- an upload is in bounded API retry/backoff;
- another process still holds a write-open file;
- the file-data bandwidth limit is unexpectedly low.

Check:

```bash
pdrive-watch
pdrive-bwlimit
pdrive-transfers
```

The decisive distinction is not “zero traffic”, but old queued work plus no
meaningful process reads, no sent TCP payload and repeated confirmation. The
watchdog applies that distinction automatically. A 100 GB file can run for many
hours without completing and must not be restarted while bytes still move.

If the queue is genuinely stuck, DNS is healthy, no TCP/read activity is
measurable and the report recommends recovery, use one controlled restart:

```bash
pdrive-watch --restart-service
```

Do not chain repeated restarts. Each one can restart a file upload and rebuild
the persistent queue inventory.

## Wi-Fi or router reconnects

Brief network loss should normally recover through rclone's bounded retries.
The monitor treats DNS failure as network evidence, not as permission for a
restart loop. Stabilize the network first; Ethernet or a lower upload rate can
help overloaded consumer routers:

```bash
pdrive-bwlimit 3
```

Remove the temporary limit later with `pdrive-bwlimit off`. Live changes do not
interrupt the current transfer.

The Control Center's **⏸ ≈0** slider endpoint is a near-pause implemented as a
`0.02 MiB/s` upload limit. rclone has no native VFS transfer pause, and its raw
value `0` means unlimited. Move the slider fully right or run
`pdrive-bwlimit off` to restore unlimited throughput.

### A link is not the same as a working route

NetworkManager can report Ethernet as connected even when no IPv4 default route
was installed, for example after address-conflict handling during resume. Before
restarting rclone to “move it to the cable”, verify the actual route and sockets:

```bash
ip route show default
nmcli device status
nmcli -f GENERAL.DEVICE,IP4.ADDRESS,IP4.GATEWAY device show
ss -tpn | grep rclone
```

Restore the desired gateway first, then perform at most one controlled rclone
restart if the existing sockets still use the unwanted interface. Plugging in a
cable alone does not migrate established TCP connections.

## Bandwidth is only a few KiB/s

Run `pdrive-bwlimit`. rclone's raw numeric bandwidth syntax can be surprising;
this helper deliberately treats every unitless component as MiB/s:

```text
4       -> 4M:off
4.2     -> 4.2M:off
4:1     -> 4M:1M
800K    -> 800K:off
```

The left side is upload and the right side is download. The units are bytes per
second. A stale value can be corrected live without restarting the mount.
PDrive's limiter applies only to bulk file payloads, so even a near-paused
upload must not hold a small directory-listing request behind it.

If uncached Nemo navigation still takes roughly as long as the global byte rate
would need for a tiny request, verify the managed build:

```bash
pdrive-prerequisites --check
```

An incompatible or official rclone replacement does not provide the required
backend command. Repair it with `pdrive-prerequisites --install-rclone`, then
perform one controlled service restart after checking that the queue and Dirty
cache are preserved. Do not add rclone's global `--bwlimit` to the mount: that
transport-level limiter also throttles Proton metadata writes.

## Nemo is slow or shows stale folders

First distinguish the two caches:

1. rclone's one-hour VFS directory cache speeds revisiting folders and tracks
   operations made through this mount;
2. the optional Proton backend metadata cache persists in process memory and
   cannot see changes made by other clients.

Nemo `F5` refreshes its view but cannot empty the deeper backend maps. After an
external Web/mobile/CLI change, run:

```bash
pdrive-refresh --refresh
```

It refuses to restart while any VFS queue, active upload or Dirty data exists.
If external writers are routine, leave the metadata cache disabled:

```bash
pdrive-recovery --disable
pdrive-watch --restart-service
```

## Nemo Extra Pane or breadcrumb mismatch

Use `/pdrive` directly. A Home-directory symlink can be classified by GIO as
the underlying home filesystem rather than the resolved FUSE mount, which can
confuse Nemo's mount-aware second-pane behavior. The root-level mount also lies
outside the locations GVfs normally presents as removable devices, so it avoids
a casual eject icon while remaining a normal FUSE mount.

## File remains Dirty or upload never appears remotely

An application may still hold the file open, the write-back delay may not have
elapsed, or the upload may be retrying. Inspect the local queue:

```bash
pdrive-watch
pdrive-refresh
```

Never remove VFS data or metadata while Dirty files exist. Cache cleanup is
safe only after the queue and Dirty counts are zero and important remote files
have been independently verified. Prefer a controlled systemd stop; avoid
`kill -9`, which prevents normal write-back and unmount cleanup.

## HTTP 401 or expired session

When Proton explicitly requires fresh 2FA, PDrive records a terminal
authentication state, cancels the pending systemd restart and sends one desktop
notification. Open PDrive Control Center and select **Reauthorize** in the
Overview banner or the then-visible **hamburger menu → Reauthorize Proton
account …**. The native
dialog reuses the configured account name and requests only the current account
password plus an optional fresh six-digit code.

Use local diagnostics first for a generic 401. A rejected root-level session
refresh is kept separate from older file-operation incidents; when the current
authenticated mount and local RC channel are healthy, it is recorded as
recovered rather than presented as an unreviewed problem. If the stored session
truly cannot refresh, the account password changed or the graphical Control
Center is unavailable, use the terminal fallback:

```bash
pdrive-reauth --reauth
```

The helper verifies a separate encrypted replacement configuration with one
bounded login attempt before it stops anything. A failed password, stale 2FA or
HTTP 429 therefore leaves the current configuration and mount untouched. After
success it stops the service, backs up the final current configuration, installs
the tested replacement atomically, removes the one-time code and validates the
new mount. Credentials travel only through anonymous stdin, never argv or the
environment.

Do not manually restart the mount before completing reauthorization. The
terminal guard exists specifically to avoid creating a new rejected Proton
login session every hour. A temporary 5xx outage, DNS failure or offline system
does not activate this guard.

Proton accounts using a two-password model distinguish the account login
password from the mailbox password. If that account mode is enabled, configure
the backend's `mailbox_password` through rclone's interactive configuration;
repeating the login password or stale 2FA code will not repair it.

## HTTP 429, CAPTCHA or too many recent logins

Stop trying. Leave the mount service stopped, wait for Proton's complete stated
backoff plus a few minutes, then make exactly one reauthentication attempt.
Rapid service retries, online doctor calls and repeated password tests can
extend the restriction or trigger additional abuse protection.

PDrive marks this state only when the isolated private login log contains a
concrete HTTP 429 status. The Overview shows the locally persisted retry time
and suppresses both the banner action and hamburger-menu bypass until then. A
manual service start cannot shorten or erase that cooldown. HTTP 422 and generic
credential rejection remain distinct and do not manufacture a rate limit.

The mount unit's one-hour restart delay and unlimited start timeout exist to
avoid such login hammering.

## Account change is blocked or rolled back

Use **Reauthorize** only for the already configured account. For an intentional
new account, open **Preferences → Account → Change Proton account …** or run:

```bash
pdrive-account-switch --switch
```

PDrive refuses while any upload, download, VFS queue entry or Dirty metadata
file exists. This is a safety result: wait for real remote completion and retry
the preflight; do not clear the queue, delete metadata or stop a healthy active
transfer to force it through. If the live RC or metadata state cannot be read,
run `pdrive-doctor` and repair observability before changing accounts.

A rejected candidate login leaves the current mount and same-account
authentication guard unchanged. A message that the **previous account was
restored** means the candidate authenticated but its new mount failed one of the
PID, writable-FUSE, RC or cache-path validation gates. Inspect service
diagnostics before another login attempt. Do not delete either cache namespace
or the encrypted rollback bundle; the old selectors have already been restored
atomically. If both the candidate and restored mount need attention, preserve
all cache roots and use `pdrive-doctor` before any manual service action.

## HTTP 422: draft or name already exists

A normal name conflict and an incomplete server-side upload draft can both
produce 422 responses. Do not immediately enable replacement.

First confirm all of the following:

- the target is an incomplete draft rather than a valid existing file;
- the complete local source is still preserved in the VFS cache or elsewhere;
- no other Proton client is writing;
- the exact VFS backend namespace for the changed options is understood;
- a normal retry or one controlled restart does not resolve it.

In exclusive metadata-cache mode, `pdrive-draft-recovery.timer` automates those
checks for the narrow, explicit `a draft exist` failure. It binds that backend
conflict to the queued file identity, size and VFS metadata inode, requires a later retry,
measures process-owned TCP, rclone-byte, process-read and filesystem-I/O deltas
over 20 seconds, validates the complete Dirty byte count and
calculates rclone's option-derived namespace from the same MD5/base64 algorithm
used by rclone v1.75.0. It then atomically renames both `vfs` and `vfsMeta`,
validates the preserved queue after restart and returns to the conservative
namespace only after the queue is clean.

If an upload later stalls inside that recovery namespace, the same timer can
perform one generation-bound restart without moving the cache again. This is
not a generic inactivity timeout. It first requires verified per-file progress,
a newer concrete upload error, healthy DNS and two separated 20-second probes
with no payload movement. Near-pause upload limits at or below 64 KiB/s, a PID
change, renewed progress, missing Dirty bytes, an unexpected namespace or an
already-used restart allowance all block the action. A changed PID must first
produce fresh progress and a later error. Files of any age and size remain
protected while they are merely slow.

The post-recovery states most useful during diagnosis are:

- `recovering`: progress is healthy or no unresolved post-progress error exists;
- `throttled` / `network-deferred`: a deliberate rate or network condition
  suppresses restart checks;
- `confirming-stall`: one zero-activity observation exists and a later one is
  still required;
- `restarted`: a new PID and the exact protected queue were validated;
- `restart-limited`: this cache generation already used its single attempt;
- `restart-failed`: the request or its strict post-restart validation failed.

### 100% transferred but still queued

The progress percentage covers payload blocks, not Proton's final commit. A
file can therefore show 100% while Proton is still creating the remote revision.
The Control Center labels this phase **Finalizing** and keeps the item in the
queue until the backend confirms success.

rclone v1.75.0 has a known Proton retry regression where a temporary 502 during
that finalization path can be followed by 422 and 404 responses. The retry could
reuse an already consumed stream, so blindly repeating the operation is unsafe.
The upstream correction is tracked in
[rclone #9722](https://github.com/rclone/rclone/issues/9722). New toolkit
installations use a pinned, checksum-verified PDrive rclone build based on the
fixed beta. Its source also pins the API bridge worker-drain correction, retries
only transiently failed encrypted blocks within the current batch and adds the
file-data-only limiter. The bridge correction is proposed upstream in
[Proton-API-Bridge #8](https://github.com/rclone/Proton-API-Bridge/pull/8), while
the dependent retry is tracked in
[PDrive #42](https://github.com/oss-singularity/proton-drive-linux/issues/42) and
the limiter's measurements and proposed backend contract are tracked in
[rclone #9832](https://github.com/rclone/rclone/issues/9832). The weekly updater
keeps this reviewed build until PDrive publishes a replacement instead of
replacing it with an incompatible official binary.

The guarded helper does not treat an ordinary 100% transfer as stalled. It
requires a terminal backend error in the completion window, a fixed rclone,
ten minutes for Proton to settle, healthy connectivity, a non-paused upload
limit and two separated zero-activity probes. It then permits at most one
finalization-specific restart for that exact cache generation. `upgrade-required`
preserves the queue without restarting; `confirming-finalization` means a second
observation is still required. Do not clear the cache or the recovery state to
force another attempt.

Inspect the automation before intervening:

```bash
systemctl --user status pdrive-draft-recovery.timer
journalctl --user -u pdrive-draft-recovery.service -n 100 --no-pager
jq . ~/.local/state/rclone/pdrive-draft-recovery-latest.json
```

The same summary is visible in **PDrive Control Center → History → Service
diagnostics → Draft recovery**. The detail tooltip explains the current gate.
Do not clear `pdrive-draft-recovery-state.json` to force another attempt: its
generation fingerprint and restart counter are safety evidence. Review the
queue, Dirty metadata, live namespace and journal before any manual restart.

If the exact conflict is already independently confirmed, the supported
accelerated path is `pdrive-draft-recovery --recover-now`. It skips the second
timer observation, not the cache or rollback guards.

`pdrive-draft-recovery --enable` remains a manual expert switch. It
intentionally does not restart rclone or relocate cache data.
`replace_existing_draft` changes remote state and also alters the cache
namespace selected by backend options. A blind restart can make the local queue
appear to vanish even though its data still exists under another cache
directory. Treat any manual namespace mapping as an audited recovery procedure.

Disable draft replacement only after every Proton Dirty file is gone. The
helper enforces that final guard.

## HTTP 5xx and storage failures

Proton or its storage layer may transiently return 500, 502 or similar errors.
The mount uses five low-level attempts and two high-level attempts to recover
without endless loops. If aggregate bytes continue to move, leave it alone.

Three separated, same-process HTTP 502 block-upload failures after proven
payload progress activate a dedicated bridge-stall guard. Two separated 502
cycles are also sufficient when Proton immediately follows them with a terminal
`This file has been removed` response: after removing that draft, the stalled
worker may be unable to emit a third cycle. One 502, an older 404 or two ordinary
server errors never satisfy this shortcut. The guard still requires healthy
DNS, bandwidth above near pause and two separated idle probes before a
controlled restart. The restart stays inside the existing recovery namespace,
preserves the exact Dirty cache generation and validates that the same queue
returns under a new PID.

This guard has an independent maximum of six restarts with a 30-minute minimum
gap. `confirming-bridge-stall` means the second idle observation is still
missing; `bridge-cooldown` means the prior bridge recovery is too recent; and
`bridge-restart-limited` deliberately stops automation for manual review. Do
not delete its state file to reset the budget, and do not reauthenticate unless
the actual error is authentication-related.

## One versus four upload slots

Four slots are normal and best for mixed workloads:

```bash
pdrive-transfers default
```

For a tiny remaining queue of exceptionally large files where one failing
parallel block repeatedly cancels all other active requests, serial recovery can
reduce the failure surface:

```bash
pdrive-transfers 1
pdrive-watch --restart-service
```

Return to four after recovery. Changing the configuration alone never restarts
the service.

## After `apt autoremove`

Package removal can break FUSE, Keyring access or monitoring even when rclone's
binary still exists. Verify both installation and manual-package status:

```bash
dpkg-query -W \
  fuse3 libfuse3-3 libsecret-tools gnome-keyring libpam-gnome-keyring \
  jq curl openssl iproute2 libnotify-bin python3-gi python3-gi-cairo gir1.2-gtk-3.0 \
  gir1.2-ayatanaappindicator3-0.1 librsvg2-common
apt-mark showmanual | grep -E \
  '^(fuse3|libfuse3-3|libsecret-tools|gnome-keyring|libpam-gnome-keyring|jq|python3-gi|python3-gi-cairo|gir1.2-gtk-3.0|gir1.2-ayatanaappindicator3-0.1|librsvg2-common)$'
```

Repair missing core packages with:

```bash
sudo apt install --reinstall \
  fuse3 libfuse3-3 libsecret-tools gnome-keyring libpam-gnome-keyring \
  jq curl openssl iproute2 libnotify-bin python3-gi python3-gi-cairo gir1.2-gtk-3.0 \
  gir1.2-ayatanaappindicator3-0.1 librsvg2-common
sudo apt-mark manual \
  fuse3 libfuse3-3 libsecret-tools gnome-keyring libpam-gnome-keyring jq \
  python3-gi python3-gi-cairo gir1.2-gtk-3.0 \
  gir1.2-ayatanaappindicator3-0.1 librsvg2-common
systemctl --user daemon-reload
pdrive-doctor
```

Do not restart the mount until queue and Dirty state are understood. Unrelated
packages such as ISO-mount, Wine or mail-client components are not dependencies
merely because they were removed in the same autoremove transaction.

## PDrive Control Center does not open or has no live data

First separate the GTK launcher from the read-only state backend:

```bash
pdrive-ui --check
pdrive-state --compact | jq '.health, .service, .mount, .queue'
```

`pdrive-ui --check` must report GTK 3 and the resolved `pdrive-state` path. If
GTK imports fail, reinstall `python3-gi` and `gir1.2-gtk-3.0` as shown above.
If the JSON reports `rc-unavailable`, verify that the normal mount owns a Unix
socket and never replace it with a TCP listener:

```bash
stat ~/.local/state/rclone/pdrive-rc.sock
systemctl --user status rclone-proton-drive.service
pdrive-watch
```

The UI intentionally remains useful with partial data and lists failed local
components in `.health.components`. Do not start a separate `rclone rcd` to
make the dashboard work; repair the existing mount service instead. The
development-only `pdrive-ui --demo` uses synthetic values and proves only that
the GTK layout works.

If the window disappears on close, check whether **Preferences → close into tray**
is enabled and open it again from Cinnamon's panel indicator. Autostart state is
inspectable without starting the UI:

```bash
cat ~/.config/pdrive-ui.json
grep -E '^(Exec|X-PDrive)' \
  ~/.config/autostart/io.github.claudiuschuster.PDriveControl.desktop
```

The expected command is `pdrive-ui --background` and the expected ownership
marker is `X-PDrive-Control-Center=true`. Delete neither file while the Settings
dialog is saving. On X11 Cinnamon the application intentionally uses GTK
StatusIcon to support left-click-to-open and a separate right-click menu. On
other display backends it uses Ayatana AppIndicator when available; reinstall
`gir1.2-ayatanaappindicator3-0.1` if that compatibility icon is missing.

If Cinnamon shows the correct icon for an existing favorite but a generic gear
for the same application in search results, inspect the menu assets:

```bash
ls -l \
  ~/.local/share/applications/io.github.claudiuschuster.PDriveControl.desktop \
  ~/.local/share/icons/hicolor/scalable/apps/io.github.claudiuschuster.PDriveControl.svg
```

Both should be regular installed files. Development symlinks into a Git checkout
can leave an already constructed Cinnamon application button stale because a
target-file edit does not change the watched applications directory. Re-running
`./install.sh` installs regular copies and refreshes the desktop database; it
does not restart the mount or interrupt transfers.

## Disk space and cache cleanup

The mount targets a 25 GiB cache and preserves at least 50 GiB free space, but
Dirty upload data cannot safely be evicted merely to satisfy a cache target.
Check:

```bash
du -sh ~/.cache/rclone
df -h "$HOME"
pdrive-cache-age
pdrive-refresh
```

An empty live queue with non-zero cache usage is normally healthy: rclone keeps
clean, already-uploaded local copies to accelerate repeated reads. PDrive
Control Center's VFS-cache section shows clean and pending data separately.
Clean files become eligible for eviction after the configured idle age (24
hours by default), while Dirty upload data is never discarded merely to meet
the age or size target. Change the next-start retention with
`pdrive-cache-age HOURS` or from that Control Center section.

Old clean backend namespaces can exist after changing Proton backend options.
Before removing one, prove it is not selected by the running process, contains
zero Dirty metadata, is absent from the live queue and is not the only local
copy of a file. When uncertain, keep it.

## Useful logs and state

```text
~/.local/state/rclone/proton-mount.log
~/.local/state/rclone/proton-mount.log.*
~/.local/state/rclone/proton-reauth.log
~/.local/state/rclone/pdrive-auth-state.json
~/.local/state/rclone/pdrive-auth-attempt
~/.local/state/rclone/pdrive-watch-latest.txt
~/.local/state/rclone/pdrive-watch-history.log
~/.local/state/rclone/pdrive-watch-state
```

`pdrive-auth-state.json` is the credential-free authentication status consumed
by the Control Center. `pdrive-auth-attempt` stores only the mount-log byte
offset at which the current service start began; it lets the guard distinguish
the current failure from an old log line. Both files are owner-only and safe to
inspect, but neither should be edited to bypass reauthorization.

The mount log rotates at 10 MiB, retains three compressed backups and expires
old rotations after 30 days. Logs can contain personal file paths. Redact them
before posting a bug report.

The watchdog history is line-bounded rather than size-rotated: it keeps the
latest 512 samples (about 32 days at the standard 90-minute timer interval).
The Control Center deliberately renders only the latest 24 of those samples.

If an interrupted older rotation left embedded NUL bytes, inspect without
rewriting the log:

```bash
tr -d '\000' < ~/.local/state/rclone/proton-mount.log | tail -n 100
```

`pdrive-watch` totals count lines in the current uncompressed mount log, not
unique files or unresolved failures. One block failure can create several ERROR
and NOTICE lines, and successful later retries do not subtract the historical
lines. The live VFS queue and Dirty count are the authoritative current state.

## Reporting an issue

Open a [PDrive GitHub issue](https://github.com/oss-singularity/proton-drive-linux/issues).
The rclone forum is for broader community discussion and upstream coordination,
not PDrive-specific support.

Include:

- distribution, desktop and rclone version;
- output of `pdrive-doctor` with personal paths redacted if needed;
- output of `pdrive-watch`;
- relevant journal and mount-log excerpts, not the complete private log;
- whether Web/mobile/CLI clients changed data concurrently;
- whether the queue or Dirty count was non-zero before a restart.

Never include `rclone.conf`, Keyring exports, Proton passwords, 2FA codes,
session tokens or complete private filenames unless they are essential and have
been safely anonymized.
