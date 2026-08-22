# Security policy

## Reporting a vulnerability

Please do not open a public issue containing a usable credential, rclone
configuration, Keyring export, Proton session token, 2FA code or private file
listing. Use GitHub's private vulnerability-reporting feature when available,
or contact the repository owner privately through the address published on the
owner's GitHub profile.

Include the smallest reproducible description, affected commit, expected
security boundary and whether the problem requires access as the logged-in
desktop user.

## Security boundaries

This project protects secrets at rest and narrows accidental control surfaces:

- `rclone.conf` is encrypted with a random secret stored in GNOME Keyring;
- the rclone RC endpoint is an owner-only Unix socket, never a TCP listener;
- the FUSE mount and local state use owner-only permissions;
- helper configuration is parsed as validated data and never sourced;
- state-changing recovery commands require explicit options and, where
  appropriate, exact terminal confirmation.

It does not defend against a process already running as the same logged-in
desktop user. Such a process can access the unlocked Keyring, invoke user
systemd, read mounted files and control same-user FUSE mounts.

The Proton Drive backend is beta and depends on external service behavior.
Always retain an independent backup of important data.
