#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the guarded draft namespace round trip without remote access."""

from __future__ import annotations

import datetime as dt
import importlib.machinery
import importlib.util
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
    service_pid = runtime / "pid"
    queue_file = runtime / "queue.json"
    transfer_file = runtime / "transfer-bytes"
    restart_count = runtime / "restart-count"
    service_state.write_text("active\n", encoding="utf-8")
    service_pid.write_text("4242\n", encoding="utf-8")
    transfer_file.write_text("0\n", encoding="utf-8")
    restart_count.write_text("0\n", encoding="utf-8")
    queue_file.write_text(
        json.dumps(
            {
                "queue": [
                    {
                        "name": "fixture/large.bin",
                        "size": 8 * 1024 * 1024,
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
    (normal_meta / "large.bin").write_text(json.dumps({"Dirty": True, "Size": 8 * 1024 * 1024}), encoding="utf-8")
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
  show) [[ "$(cat {service_state})" == active ]] && cat {service_pid} || printf '0\\n' ;;
  stop) printf 'inactive\\n' > {service_state} ;;
  start) printf 'active\\n' > {service_state} ;;
  restart)
    printf 'active\\n' > {service_state}
    printf '%s\\n' "$(( $(cat {service_pid}) + 1 ))" > {service_pid}
    printf '%s\\n' "$(( $(cat {restart_count}) + 1 ))" > {restart_count}
    ;;
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
    executable(fake_bin / "getent", "#!/usr/bin/env bash\nprintf '192.0.2.1 STREAM drive-api.proton.me\\n'\n")
    fake_rclone = fake_bin / "rclone"
    executable(
        fake_rclone,
        f"""#!/usr/bin/env bash
set -euo pipefail
endpoint="${{@: -1}}"
mode="$(awk -F= '$1 == "replace_existing_draft" {{ print $2 }}' {config / "pdrive-draft-recovery.conf"})"
if [[ "${{mode}}" == true ]]; then namespace='{recovery}'; else namespace='{normal}'; fi
case "${{endpoint}}" in
  version) printf 'rclone v1.76.0-beta.10204.660144d31\n' ;;
  vfs/queue) cat {queue_file} ;;
  vfs/stats) printf '{{"diskCache":{{"path":"{cache}/vfs/%s","pathMeta":"{cache}/vfsMeta/%s"}}}}\\n' "${{namespace}}" "${{namespace}}" ;;
  core/stats) printf '{{"bytes":%s,"transferring":[{{"name":"fixture/large.bin","size":8388608,"bytes":%s,"startedAt":"2026-08-26T08:00:00+02:00"}}]}}\\n' "$(cat {transfer_file})" "$(cat {transfer_file})" ;;
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
            "PDRIVE_POST_RECOVERY_MIN_CONFIRMATION_SECONDS": "0",
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

    transfer_file.write_text(f"{2 * 1024 * 1024}\n", encoding="utf-8")
    error_time = (dt.datetime.now().astimezone() + dt.timedelta(seconds=2)).strftime("%Y/%m/%d %H:%M:%S")
    with (state / "proton-mount.log").open("a", encoding="utf-8") as stream:
        stream.write(f"{error_time} ERROR : fixture/large.bin: vfs cache: failed to upload try #9, will retry\n")
    for expected_confirmation in (1, 2):
        completed = subprocess.run(
            [str(HELPER), "--auto"],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
            timeout=20,
        )
        assert completed.returncode == 0, completed.stderr or completed.stdout
        latest = json.loads((state / "pdrive-draft-recovery-latest.json").read_text(encoding="utf-8"))
        if expected_confirmation == 1:
            assert latest["status"] == "confirming-stall", latest
            assert latest["stall_confirmations"] == 1, latest
        else:
            assert latest["status"] == "restarted", latest
            assert latest["restart_attempts"] == 1, latest
    assert restart_count.read_text(encoding="utf-8").strip() == "1"
    assert service_pid.read_text(encoding="utf-8").strip() == "4243"

    queue_file.write_text('{"queue": []}\n', encoding="utf-8")
    (cache / "vfsMeta" / recovery / "fixture/large.bin").write_text(
        json.dumps({"Dirty": False, "Size": 8 * 1024 * 1024}), encoding="utf-8"
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


loader = importlib.machinery.SourceFileLoader("pdrive_draft_recovery_auto", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

assert module.parse_bandwidth_component("0.020Mi") == int(0.020 * 1024**2)
assert module.parse_bandwidth_component("4.200Mi") == int(4.2 * 1024**2)
assert module.parse_bandwidth_component("off") is None
assert not module.upload_retry_safe_version("v1.75.0")
assert not module.upload_retry_safe_version("v1.76.0-beta.10203.example")
assert module.upload_retry_safe_version("v1.76.0-beta.10204.660144d31")
assert module.upload_retry_safe_version("v1.76.0")
assert module.upload_retry_safe_version("v1.77.0-beta.1.example")
assert not module.upload_retry_safe_version("unexpected")

legacy_intermediate_state = {
    "state_version": 2,
    "phase": "recovery",
    "fingerprint": "a" * 64,
    "recovery_started_epoch": 10_000,
    "progress_proven": True,
}
assert module.recovery_baseline_epoch(legacy_intermediate_state, "a" * 64, 8_000, 12_000) == 8_000
valid_transition_state = {**legacy_intermediate_state, "baseline_source": "transition"}
assert module.recovery_baseline_epoch(valid_transition_state, "a" * 64, 8_000, 12_000) == 10_000


def observation(**overrides: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "now_epoch": 10_000,
        "fingerprint": "a" * 64,
        "pid": 4242,
        "tries": 8,
        "queue_count": 1,
        "queue_bytes": 100 * 1024**3,
        "candidate_size": 100 * 1024**3,
        "transfer_bytes": 2 * 1024**3,
        "transfer_started_epoch": 8_000,
        "baseline_source": "transfer-start",
        "error_epoch": 0,
        "error_category": "none",
        "error_signature": "",
        "upload_limit": None,
        "connectivity_healthy": True,
        "upload_retry_safe": True,
        "activity": "not-probed",
    }
    payload.update(overrides)
    return payload


healthy = module.post_recovery_decision({}, observation())
assert healthy["status"] == "recovering" and not healthy["probe"] and not healthy["restart"]

near_pause = module.post_recovery_decision(
    {}, observation(error_epoch=9_000, error_category="remote-server", upload_limit=20 * 1024)
)
assert near_pause["status"] == "throttled" and not near_pause["restart"]

first_idle = module.post_recovery_decision(
    {}, observation(error_epoch=9_000, error_category="remote-file-removed", activity="idle")
)
assert first_idle["status"] == "confirming-stall"
assert first_idle["state"]["zero_activity_confirmations"] == 1

too_soon = module.post_recovery_decision(
    first_idle["state"],
    observation(now_epoch=10_030, error_epoch=9_000, activity="idle"),
)
assert too_soon["state"]["zero_activity_confirmations"] == 1 and not too_soon["restart"]

confirmed = module.post_recovery_decision(
    first_idle["state"],
    observation(now_epoch=10_300, error_epoch=9_000, activity="idle"),
)
assert confirmed["restart"] and confirmed["state"]["restart_attempts"] == 1

cooldown = module.post_recovery_decision(
    confirmed["state"],
    observation(now_epoch=11_000, error_epoch=10_500, activity="idle"),
)
assert cooldown["status"] == "cooldown" and not cooldown["restart"]

limited = module.post_recovery_decision(
    confirmed["state"],
    observation(now_epoch=60_000, error_epoch=59_000, activity="idle"),
)
assert limited["status"] == "restart-limited" and not limited["restart"]

combined_bridge_first = module.post_recovery_decision(
    confirmed["state"],
    observation(
        now_epoch=60_000,
        error_epoch=59_010,
        error_category="remote-file-removed",
        bridge_failure_cycles=2,
        last_bridge_failure_epoch=59_000,
        activity="idle",
    ),
)
assert combined_bridge_first["status"] == "confirming-bridge-stall"
assert combined_bridge_first["state"]["bridge_stall_confirmations"] == 1
combined_bridge_confirmed = module.post_recovery_decision(
    combined_bridge_first["state"],
    observation(
        now_epoch=60_300,
        error_epoch=59_010,
        error_category="remote-file-removed",
        bridge_failure_cycles=2,
        last_bridge_failure_epoch=59_000,
        activity="idle",
    ),
)
assert combined_bridge_confirmed["status"] == "bridge-restart-requested"
assert combined_bridge_confirmed["restart_kind"] == "bridge-unwedge"

combined_bridge_moving = module.post_recovery_decision(
    combined_bridge_first["state"],
    observation(
        now_epoch=60_300,
        error_epoch=59_010,
        error_category="remote-file-removed",
        bridge_failure_cycles=2,
        last_bridge_failure_epoch=59_000,
        activity="moving",
    ),
)
assert combined_bridge_moving["status"] == "recovering"
assert not combined_bridge_moving["restart"]

single_bridge_cycle = module.post_recovery_decision(
    confirmed["state"],
    observation(
        now_epoch=60_000,
        error_epoch=59_010,
        error_category="remote-file-removed",
        bridge_failure_cycles=1,
        last_bridge_failure_epoch=59_000,
        activity="idle",
    ),
)
assert single_bridge_cycle["status"] == "restart-limited"

stale_terminal_error = module.post_recovery_decision(
    confirmed["state"],
    observation(
        now_epoch=60_000,
        error_epoch=58_900,
        error_category="remote-file-removed",
        bridge_failure_cycles=2,
        last_bridge_failure_epoch=59_000,
        activity="idle",
    ),
)
assert stale_terminal_error["status"] == "restart-limited"

two_remote_server_cycles = module.post_recovery_decision(
    confirmed["state"],
    observation(
        now_epoch=60_000,
        error_epoch=59_010,
        error_category="remote-server",
        bridge_failure_cycles=2,
        last_bridge_failure_epoch=59_000,
        activity="idle",
    ),
)
assert two_remote_server_cycles["status"] == "restart-limited"

bridge_first_idle = module.post_recovery_decision(
    {},
    observation(
        error_epoch=9_000,
        error_category="remote-server",
        bridge_failure_cycles=3,
        last_bridge_failure_epoch=9_000,
        activity="idle",
    ),
)
assert bridge_first_idle["status"] == "confirming-bridge-stall"
assert bridge_first_idle["state"]["bridge_stall_confirmations"] == 1

bridge_state = dict(bridge_first_idle["state"])
bridge_state["restart_attempts"] = 1
bridge_state["last_restart_epoch"] = 10_200
bridge_confirmed = module.post_recovery_decision(
    bridge_state,
    observation(
        now_epoch=10_300,
        error_epoch=9_000,
        error_category="remote-server",
        bridge_failure_cycles=3,
        last_bridge_failure_epoch=9_000,
        activity="idle",
    ),
)
assert bridge_confirmed["status"] == "bridge-restart-requested"
assert bridge_confirmed["restart"] and bridge_confirmed["restart_kind"] == "bridge-unwedge"
assert bridge_confirmed["state"]["bridge_unwedge_restart_attempts"] == 1

bridge_cooldown = module.post_recovery_decision(
    bridge_confirmed["state"],
    observation(
        now_epoch=10_600,
        error_epoch=10_500,
        error_category="remote-server",
        bridge_failure_cycles=3,
        last_bridge_failure_epoch=10_500,
        activity="idle",
    ),
)
assert bridge_cooldown["status"] == "bridge-cooldown" and not bridge_cooldown["restart"]

bridge_limited_state = dict(bridge_confirmed["state"])
bridge_limited_state["bridge_unwedge_restart_attempts"] = module.POST_BRIDGE_STALL_RESTART_LIMIT
bridge_limited = module.post_recovery_decision(
    bridge_limited_state,
    observation(
        now_epoch=20_000,
        error_epoch=19_900,
        error_category="remote-server",
        bridge_failure_cycles=3,
        last_bridge_failure_epoch=19_900,
        activity="idle",
    ),
)
assert bridge_limited["status"] == "bridge-restart-limited" and not bridge_limited["restart"]

bridge_moving = module.post_recovery_decision(
    bridge_first_idle["state"],
    observation(
        now_epoch=10_300,
        error_epoch=9_000,
        error_category="remote-server",
        bridge_failure_cycles=3,
        last_bridge_failure_epoch=9_000,
        activity="moving",
    ),
)
assert bridge_moving["status"] == "recovering"
assert bridge_moving["state"]["bridge_stall_confirmations"] == 0

moving = module.post_recovery_decision(
    first_idle["state"],
    observation(now_epoch=10_300, error_epoch=9_000, activity="moving"),
)
assert moving["status"] == "recovering"
assert moving["state"]["zero_activity_confirmations"] == 0
assert moving["state"]["last_error_epoch"] == 0

payload_size = 100 * 1024**3
finalizing = module.post_recovery_decision(
    {},
    observation(
        now_epoch=20_000,
        transfer_bytes=payload_size,
        candidate_size=payload_size,
        error_epoch=0,
    ),
)
assert finalizing["status"] == "finalizing"
assert not finalizing["probe"] and not finalizing["restart"]

finalization_grace = module.post_recovery_decision(
    {},
    observation(
        now_epoch=20_000,
        transfer_bytes=payload_size,
        candidate_size=payload_size,
        error_epoch=19_900,
        error_category="remote-file-removed",
    ),
)
assert finalization_grace["status"] == "finalizing"
assert finalization_grace["state"]["finalization_error_epoch"] == 19_900

unsafe_retry = module.post_recovery_decision(
    finalization_grace["state"],
    observation(
        now_epoch=21_000,
        transfer_bytes=payload_size,
        candidate_size=payload_size,
        error_epoch=19_900,
        error_category="remote-file-removed",
        upload_retry_safe=False,
        activity="idle",
    ),
)
assert unsafe_retry["status"] == "upgrade-required" and not unsafe_retry["restart"]

finalization_first_idle = module.post_recovery_decision(
    finalization_grace["state"],
    observation(
        now_epoch=21_000,
        transfer_bytes=payload_size,
        candidate_size=payload_size,
        error_epoch=19_900,
        error_category="remote-file-removed",
        activity="idle",
    ),
)
assert finalization_first_idle["status"] == "confirming-finalization"
assert finalization_first_idle["state"]["finalization_confirmations"] == 1

finalization_confirmed = module.post_recovery_decision(
    finalization_first_idle["state"],
    observation(
        now_epoch=21_300,
        transfer_bytes=payload_size,
        candidate_size=payload_size,
        error_epoch=19_900,
        error_category="remote-file-removed",
        activity="idle",
    ),
)
assert finalization_confirmed["restart"]
assert finalization_confirmed["restart_kind"] == "finalization"
assert finalization_confirmed["state"]["finalization_restart_attempts"] == 1

finalization_limited = module.post_recovery_decision(
    finalization_confirmed["state"],
    observation(
        now_epoch=23_500,
        transfer_bytes=payload_size,
        candidate_size=payload_size,
        error_epoch=23_400,
        error_category="remote-file-removed",
        activity="idle",
    ),
)
assert finalization_limited["status"] == "finalization-restart-limited"
assert not finalization_limited["restart"]

finalization_moving = module.post_recovery_decision(
    finalization_first_idle["state"],
    observation(
        now_epoch=21_300,
        transfer_bytes=payload_size,
        candidate_size=payload_size,
        error_epoch=19_900,
        error_category="remote-file-removed",
        activity="moving",
    ),
)
assert finalization_moving["status"] == "finalizing"
assert finalization_moving["state"]["finalization_confirmations"] == 0
assert finalization_moving["state"]["finalization_error_epoch"] == 19_900

stale_finalization_error = module.post_recovery_decision(
    {},
    observation(
        now_epoch=20_000,
        transfer_bytes=payload_size,
        candidate_size=payload_size,
        error_epoch=18_000,
        error_category="remote-file-removed",
        activity="idle",
    ),
)
assert stale_finalization_error["status"] == "finalizing"
assert not stale_finalization_error["probe"] and not stale_finalization_error["restart"]

changed = module.post_recovery_decision(
    first_idle["state"],
    observation(now_epoch=10_300, pid=5151, error_epoch=9_000, activity="idle"),
)
assert changed["status"] == "process-changed"
assert changed["state"]["zero_activity_confirmations"] == 0
assert changed["state"]["progress_proven"] is False
assert changed["state"]["last_error_epoch"] == 0

offline = module.post_recovery_decision({}, observation(error_epoch=9_000, connectivity_healthy=False, activity="idle"))
assert offline["status"] == "network-deferred" and not offline["restart"]

with tempfile.TemporaryDirectory(prefix="proton-drive-linux-context-") as context_name:
    context_log = pathlib.Path(context_name) / "mount.log"
    context_log.write_text(
        "2026/08/26 02:39:09 ERROR : proton drive root link ID '': "
        "404 POST https://storage.invalid/blocks: This file has been removed. (Status=404)\n",
        encoding="utf-8",
    )
    module.MOUNT_LOG = context_log
    context_epoch = int(dt.datetime(2026, 8, 26, 2, 0, tzinfo=dt.datetime.now().astimezone().tzinfo).timestamp())
    assert module.post_recovery_error("fixture.bin", context_epoch)["epoch"] == 0
    contextual_error = module.post_recovery_error("fixture.bin", context_epoch, allow_backend_context=True)
    assert contextual_error["category"] == "remote-file-removed"

    context_log.write_text(
        "2026/08/26 02:39:09 ERROR : proton drive root link ID '': "
        "502 POST https://storage.invalid/storage/blocks: failed\n"
        "2026/08/26 02:39:20 ERROR : proton drive root link ID '': "
        "502 POST https://storage.invalid/storage/blocks: duplicate\n"
        "2026/08/26 02:40:09 ERROR : proton drive root link ID '': "
        "502 POST https://storage.invalid/storage/blocks: failed\n"
        "2026/08/26 02:41:09 ERROR : proton drive root link ID '': "
        "502 POST https://storage.invalid/storage/blocks: failed\n"
        "2026/08/26 02:42:09 ERROR : proton drive root link ID '': "
        "502 POST https://drive-api.invalid/core/v4/users: unrelated\n",
        encoding="utf-8",
    )
    bridge_summary = module.bridge_failure_summary("fixture.bin", context_epoch, allow_backend_context=True)
    assert bridge_summary["cycles"] == 3

probe_changed = module.post_recovery_decision(
    first_idle["state"],
    observation(now_epoch=10_300, error_epoch=9_000, activity="process-changed"),
)
assert probe_changed["status"] == "process-changed"
assert probe_changed["state"]["zero_activity_confirmations"] == 0

validation_queue = [{"name": "fixture.bin", "size": 4096, "tries": 4}]
validation_actions: list[str] = []
module.service_pid_and_args = lambda: (
    4242,
    "rclone mount --protondrive-replace-existing-draft=true",
)
module.rc = lambda endpoint: {"diskCache": {"path": str(module.CACHE_DIR / "vfs" / module.namespace_name(True, True))}}
module.dirty_stats = lambda _root: (1, 4096)
module.item_fingerprint = lambda _item, _metadata, _draft: "b" * 64
module.service_action = validation_actions.append


def fail_validation(*_args: object, **_kwargs: object) -> object:
    raise module.RecoveryError("fixture validation failure")


module.wait_ready = fail_validation
try:
    module.restart_recovery_service(validation_queue, True, "b" * 64)
except module.RecoveryError as error:
    assert "fixture validation failure" in str(error)
else:
    raise AssertionError("A failed post-restart validation must abort recovery")
assert validation_actions == ["restart"]

print("Guarded draft-recovery namespace checks passed.")
