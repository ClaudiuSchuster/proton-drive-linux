# Security policy

PDrive handles an encrypted rclone configuration, a login-unlocked GNOME
Keyring secret and filesystem paths that may contain private data. Please use a
private channel for anything that could expose one of those assets.

## Supported versions

Security fixes target the latest published release and the current `main`
branch. Older releases may be useful for comparison but do not receive separate
security backports while the project is in its pre-1.0 phase.

| Version        | Security support                    |
| -------------- | ----------------------------------- |
| Latest release | Supported                           |
| Current `main` | Supported development branch        |
| Older releases | Upgrade to the latest release first |

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/oss-singularity/proton-drive-linux/security/advisories/new)
when possible. If that channel is unavailable, contact the repository owner
privately through the address published on the owner's GitHub profile.

Do not open a public issue containing any of the following:

- a Proton password, current or historical 2FA code, session token or CAPTCHA;
- `rclone.conf`, its cleartext contents or the Keyring encryption secret;
- a Keyring export, private file listing, share identifier or unredacted URL;
- a diagnostic bundle or screenshot that contains personal paths or account
  information.

Include the smallest reproducible description, affected release or commit,
Linux distribution, rclone version, expected security boundary and whether the
issue requires access as the logged-in desktop user. Explain the potential
impact and any safe reproduction constraints. A synthetic test account or
fixture is strongly preferred over real cloud data.

Please allow a reasonable private investigation window before public
disclosure. This community project cannot promise a response SLA, but reports
will be handled carefully and credited when desired.

## Security boundaries

The project narrows accidental control and disclosure surfaces:

- `rclone.conf` is encrypted with a random secret stored in GNOME Keyring;
- setup and reauthentication transport credentials through anonymous stdin
  pipes, never through process arguments or environment variables;
- reauthentication verifies an isolated replacement configuration before it
  stops the working mount or replaces the current encrypted configuration;
- the rclone RC endpoint is a mode-0700 owner-only Unix socket and is never a
  TCP listener;
- `/pdrive`, helper settings, logs, state and temporary credential files use
  owner-only permissions where private content may be present;
- helper configuration is parsed as narrowly validated data and never sourced
  as shell code;
- issue evidence is bounded and sanitized before entering the UI;
- state-changing recovery commands require explicit options and, where
  appropriate, exact terminal confirmation;
- updater services run with restricted systemd sandboxes. The FUSE mount is
  deliberately exempt from incompatible restrictions that would block
  `/dev/fuse`, `fusermount3`, GNOME Keyring or the user's cache.

The weekly rclone updater relies on rclone's signed stable self-update channel.
The optional Proton Drive CLI updater accepts only an expected official
`proton.me` x86-64 URL and verifies the SHA-512 value published on the same TLS
release page. That checksum is an integrity check, not an independent signature
or a substitute for Proton's own release security.

## Out of scope and inherited risk

The project does not defend against a malicious process already running as the
same logged-in desktop user. Such a process can access the unlocked Keyring,
invoke user systemd, inspect mounted files, connect to owner-only sockets and
control same-user FUSE mounts.

Proton service behavior, the rclone Proton Drive backend, the Linux kernel,
FUSE, GNOME Keyring and distribution packages are external trust boundaries.
Report an upstream vulnerability to its owner; also report it here privately if
PDrive's integration makes the impact worse or needs a defensive change.

Availability problems, beta-backend incompatibilities and failed uploads are
not automatically security vulnerabilities, but data-loss risks are treated
seriously. Never delete Dirty VFS cache data as a generic repair, and always
retain an independent backup of important files.
