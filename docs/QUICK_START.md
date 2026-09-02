# Quick start

This page takes a new PDrive installation from zero to one verified remote
upload. Detailed maintenance belongs in [Operations](OPERATIONS.md), not here.

> [!IMPORTANT]
> PDrive is an independent community project, not an official Proton product.
> rclone labels its Proton Drive backend as beta. Keep an independent backup of
> important data.

## 1. Install

The supported target is Linux Mint 22.x with Cinnamon, Nemo and a graphical
login. Arch Linux and Ubuntu are active portability targets. The Arch Linux
`0.8.2-1` candidate preserves the package baseline whose `0.8.0-1` build passed
its clean Cinnamon/X11 desktop gate. It is ready for configured real-world
review, but Arch is not yet a generally supported release target; see
[Distribution portability](PORTABILITY.md).

```bash
git clone https://github.com/oss-singularity/proton-drive-linux.git
cd proton-drive-linux
./install.sh
pdrive-ui
```

For the reviewed Arch candidate, download
`proton-drive-linux-0.8.2-1-any.pkg.tar.zst` from the
[`v0.8.2` release](https://github.com/oss-singularity/proton-drive-linux/releases/tag/v0.8.2),
verify its published SHA-256 and replace the source-install commands above with:

```bash
sudo pacman -U ./proton-drive-linux-0.8.2-1-any.pkg.tar.zst
pdrive-ui
```

The installer may request administrator approval once to create the owner-only
`/pdrive` mountpoint. Personal rclone configuration, credentials, cache and
state are preserved when the installer is run again.

## 2. Complete the setup wizard

On first launch, PDrive Control Center guides you through these steps:

1. Check the required Mint, GTK, FUSE and Keyring components.
2. Install missing packages through the system Polkit prompt when needed.
3. Prepare the checksum-verified PDrive rclone build.
4. Choose **Auto-tune**, **Set manually** or **Unlimited** for file transfers.
5. Enter your Proton username, password and optional fresh six-digit 2FA code.
6. Wait until the wizard confirms that `/pdrive` is mounted.

Auto-tune runs one disclosed, bounded Cloudflare test of about 72 MB, then
assigns 60% of conservative measured upload and download rates to bulk file
data. The remaining 40% stays available to Nemo metadata requests and other
applications. Manual mode offers separate logarithmic upload and download
controls; Unlimited leaves both directions open. These choices affect file
payloads only, not Proton login, directory listing or other API metadata.

<img src="assets/pdrive-setup-wizard.png"
     width="700"
     alt="PDrive setup wizard showing separate manual upload and download controls">

Credentials travel through private anonymous pipes. They never appear in
process arguments, environment variables or logs.

## 3. Open Proton Drive in Nemo

Select **Open PDrive folder** in the Control Center. Nemo opens `/pdrive`, the
single owner-only filesystem backed by your Proton Drive account. The separate
**Open Proton Drive web** action is for account settings and workflows that do
not belong to the mount.

<img src="assets/pdrive-control-center.png"
     width="700"
     alt="PDrive Control Center showing a ready mount">

## 4. Verify the first upload

1. Copy one small test file into `/pdrive` with Nemo.
2. Open **Transfers** and watch the file move through Active and Queue.
3. Wait until Active is zero, Queue is empty and the file appears under
   **Recently completed** with **Upload** and **Completed** badges. Successful
   uploads remain visible there for up to 24 hours across a normal restart.
4. For important data, also verify the file in the official Proton Drive web
   client.

A finished Nemo copy means the local VFS cache accepted the data. It does not
mean Proton has committed the remote file yet. Dirty upload data stays protected
in the local cache across ordinary service recovery.

## 5. Know the protected login state

When Proton requires a fresh login, PDrive stops automatic retries before they
can repeatedly hit the account. The Overview shows the protected state and the
Control Center offers one guided reauthorization.

<img src="assets/pdrive-auth-cooldown.png"
     width="700"
     alt="PDrive Control Center protecting a Proton authentication cooldown">

If Proton rate-limits login attempts, wait until the displayed retry time. Do
not bypass the cooldown with manual service starts. The encrypted configuration
and local upload cache remain untouched while login is paused.

Reauthorization keeps the same account. To intentionally move `/pdrive` to a
different Proton account, first wait for zero Active transfers, an empty Queue
and no pending VFS data, then use **Preferences → Account → Change Proton
account …**. PDrive gives the candidate a separate cache namespace; it never
relabels the previous account's cached files as belonging to the new account.

## Where to go next

- [Everyday use](EVERYDAY_USE.md) explains Nemo, transfers, cache and routine
  notifications.
- [Troubleshooting](TROUBLESHOOTING.md) starts from a visible symptom.
- [Operations](OPERATIONS.md) contains every setting, guarded action and helper.
- [Online project documentation](https://github.com/oss-singularity/proton-drive-linux#documentation-and-development)
  remains available when you want the complete repository view.
