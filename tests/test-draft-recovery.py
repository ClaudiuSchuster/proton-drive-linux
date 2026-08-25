#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the guarded draft namespace round trip without remote access."""

from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import subprocess
import tempfile


PROJECT = pathlib.Path(__file__).resolve().parent.parent
HELPER = PROJECT / "libexec/pdrive-draft-recovery-auto"


def executable(path: pathlib.Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


with tempfile.TemporaryDirectory(prefix="proton-drive-linux-draft-") as temporary_name:
    root = pathlib.Path(temporary_name)
    home = root / "home"
    state = home / ".local/state/rclone"
    config = home / ".config"
    cache = home / ".cache/rclone"
    fake_bin = root / "bin"
    runtime = root / "runtime"
    for path in (state, config, cache / "vfs", cache / "vfsMeta", fake_bin, runtime):
        path.mkdir(parents=True, exist_ok=True)

    service_state = runtime / "service"
    queue_file = runtime / "queue.json"
    service_state.write_text("active\n", encoding="utf-8")
    queue_file.write_text(
        json.dumps(
            {
                "queue": [
                    {
                        "name": "fixture/large.bin",
                        "size": 4096,
                        "tries": 8,
                        "uploading": True,
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    (config / "pdrive-recovery.conf").write_text("proton_metadata_cache=true\n", encoding="utf-8")
    (config / "pdrive-draft-recovery.conf").write_text("replace_existing_draft=false\n", encoding="utf-8")

    normal = "proton{VyrwC}"
    recovery = "proton{53kVE}"
    normal_data = cache / "vfs" / normal / "fixture"
    normal_meta = cache / "vfsMeta" / normal / "fixture"
    normal_data.mkdir(parents=True)
    normal_meta.mkdir(parents=True)
    (normal_data / "large.bin").write_bytes(b"fixture payload")
    (normal_meta / "large.bin").write_text(json.dumps({"Dirty": True, "Size": 4096}), encoding="utf-8")
    now = dt.datetime.now().astimezone().strftime("%Y/%m/%d %H:%M:%S")
    (state / "proton-mount.log").write_text(
        f"{now} ERROR : fixture/large.bin: a draft exist - failed upload attempt\n",
        encoding="utf-8",
    )

    executable(
        fake_bin / "systemctl",
        f"""#!/usr/bin/env bash
set -euo pipefail
case "${{2:-}}" in
  show) [[ "$(cat {service_state})" == active ]] && printf '4242\\n' || printf '0\\n' ;;
  stop) printf 'inactive\\n' > {service_state} ;;
  start) printf 'active\\n' > {service_state} ;;
  *) exit 2 ;;
esac
""",
    )
    executable(
        fake_bin / "ps",
        f"""#!/usr/bin/env bash
set -euo pipefail
mode="$(awk -F= '$1 == "replace_existing_draft" {{ print $2 }}' {config / "pdrive-draft-recovery.conf"})"
printf 'rclone mount --protondrive-enable-caching=true --protondrive-replace-existing-draft=%s\\n' "${{mode}}"
""",
    )
    executable(fake_bin / "ss", "#!/usr/bin/env bash\nexit 0\n")
    fake_rclone = fake_bin / "rclone"
    executable(
        fake_rclone,
        f"""#!/usr/bin/env bash
set -euo pipefail
endpoint="${{@: -1}}"
mode="$(awk -F= '$1 == "replace_existing_draft" {{ print $2 }}' {config / "pdrive-draft-recovery.conf"})"
if [[ "${{mode}}" == true ]]; then namespace='{recovery}'; else namespace='{normal}'; fi
case "${{endpoint}}" in
  vfs/queue) cat {queue_file} ;;
  vfs/stats) printf '{{"diskCache":{{"path":"{cache}/vfs/%s","pathMeta":"{cache}/vfsMeta/%s"}}}}\\n' "${{namespace}}" "${{namespace}}" ;;
  *) exit 2 ;;
esac
""",
    )

    environment = dict(os.environ)
    environment.update(
        {
            "HOME": str(home),
            "PATH": f"{fake_bin}:/usr/bin:/bin",
            "PDRIVE_STATE_DIR": str(state),
            "PDRIVE_CONFIG_DIR": str(config),
            "PDRIVE_CACHE_DIR": str(cache),
            "PDRIVE_RC_SOCKET": str(state / "pdrive-rc.sock"),
            "PDRIVE_RCLONE_BIN": str(fake_rclone),
            "PDRIVE_MOUNT_LOG": str(state / "proton-mount.log"),
            "PDRIVE_ACTIVITY_PROBE_SECONDS": "0",
            "PYTHONDONTWRITEBYTECODE": "1",
        }
    )

    completed = subprocess.run(
        [str(HELPER), "--recover-now"],
        check=False,
        capture_output=True,
        text=True,
        env=environment,
        timeout=20,
    )
    assert completed.returncode == 0, completed.stderr or completed.stdout
    assert "replace_existing_draft=true" in (config / "pdrive-draft-recovery.conf").read_text(encoding="utf-8")
    assert not (cache / "vfs" / normal).exists()
    assert (cache / "vfs" / recovery / "fixture/large.bin").read_bytes() == b"fixture payload"
    assert (cache / "vfsMeta" / recovery / "fixture/large.bin").is_file()
    assert service_state.read_text(encoding="utf-8").strip() == "active"

    queue_file.write_text('{"queue": []}\n', encoding="utf-8")
    (cache / "vfsMeta" / recovery / "fixture/large.bin").write_text(
        json.dumps({"Dirty": False, "Size": 4096}), encoding="utf-8"
    )
    completed = subprocess.run(
        [str(HELPER), "--auto"],
        check=False,
        capture_output=True,
        text=True,
        env=environment,
        timeout=20,
    )
    assert completed.returncode == 0, completed.stderr or completed.stdout
    assert "replace_existing_draft=false" in (config / "pdrive-draft-recovery.conf").read_text(encoding="utf-8")
    assert not (cache / "vfs" / recovery).exists()
    assert (cache / "vfs" / normal / "fixture/large.bin").read_bytes() == b"fixture payload"
    assert service_state.read_text(encoding="utf-8").strip() == "active"

print("Guarded draft-recovery namespace checks passed.")
