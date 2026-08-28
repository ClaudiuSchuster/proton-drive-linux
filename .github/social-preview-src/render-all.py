#!/usr/bin/env python3
"""Render or verify every configured PDrive social-preview variant."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if a committed preview differs from a fresh render",
    )
    return parser.parse_args()


def configured_output(repo_dir: Path, value: object) -> Path:
    relative = Path(str(value))
    if relative.is_absolute():
        raise SystemExit(f"Preview output must be repository-relative: {relative}")

    output = (repo_dir / relative).resolve()
    try:
        output.relative_to(repo_dir)
    except ValueError as error:
        raise SystemExit(f"Preview output escapes the repository: {relative}") from error
    return output


def render(render_script: Path, variant: str, output: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(render_script),
            "--variant",
            variant,
            "--output",
            str(output),
        ],
        check=True,
    )


def main() -> int:
    args = parse_args()
    source_dir = Path(__file__).resolve().parent
    repo_dir = source_dir.parents[1].resolve()
    render_script = source_dir / "render.py"
    variants = json.loads((source_dir / "variants.json").read_text(encoding="utf-8"))

    if not isinstance(variants, dict) or not variants:
        raise SystemExit("At least one social-preview variant must be configured.")

    if not args.check:
        for name in sorted(variants):
            output = configured_output(repo_dir, variants[name]["output"])
            render(render_script, name, output)
        return 0

    stale: list[Path] = []
    with tempfile.TemporaryDirectory(prefix="pdrive-social-preview-check-") as temporary:
        check_dir = Path(temporary)
        for name in sorted(variants):
            committed = configured_output(repo_dir, variants[name]["output"])
            candidate = check_dir / f"{name}.png"
            render(render_script, name, candidate)
            if not committed.is_file() or committed.read_bytes() != candidate.read_bytes():
                stale.append(committed)

    if stale:
        for output in stale:
            print(f"Stale social preview: {output.relative_to(repo_dir)}", file=sys.stderr)
        print("Run make social-preview and commit the results.", file=sys.stderr)
        return 1

    print(f"All {len(variants)} social-preview variants are current.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
