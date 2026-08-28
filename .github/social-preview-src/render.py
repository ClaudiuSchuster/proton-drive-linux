#!/usr/bin/env python3
"""Render a deterministic PDrive social-preview variant."""

from __future__ import annotations

import argparse
import html
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

WIDTH = 1280
HEIGHT = 640


def parse_args(variants: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=variants, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def image_magick() -> list[str]:
    executable = shutil.which("magick") or shutil.which("convert")
    if not executable:
        raise SystemExit("ImageMagick is required (magick or convert).")
    return [executable]


def main() -> int:
    source_dir = Path(__file__).resolve().parent
    repo_dir = source_dir.parents[1]
    variants = json.loads((source_dir / "variants.json").read_text(encoding="utf-8"))
    args = parse_args(sorted(variants))
    variant = variants[args.variant]

    background = source_dir / "background.png"
    icon = repo_dir / "share/icons/hicolor/scalable/apps/io.github.claudiuschuster.PDriveControl.svg"
    if not background.is_file() or not icon.is_file():
        raise SystemExit("Social-preview background or PDrive icon is missing.")

    badge_width = int(variant["badge_width"])
    second_x = 76 + badge_width + 13
    third_x = second_x + 208 + 13
    replacements = {
        "{{TAGLINE}}": html.escape(str(variant["tagline"])),
        "{{BADGE}}": html.escape(str(variant["badge"])),
        "{{BADGE_WIDTH}}": str(badge_width),
        "{{BADGE_CENTER}}": str(76 + badge_width / 2),
        "{{SECOND_X}}": str(second_x),
        "{{SECOND_CENTER}}": str(second_x + 104),
        "{{THIRD_X}}": str(third_x),
        "{{THIRD_CENTER}}": str(third_x + 75),
    }
    overlay_text = (source_dir / "overlay.svg").read_text(encoding="utf-8")
    for marker, value in replacements.items():
        overlay_text = overlay_text.replace(marker, value)

    command = image_magick()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pdrive-social-preview-") as temporary:
        work_dir = Path(temporary)
        overlay_svg = work_dir / "overlay.svg"
        overlay_png = work_dir / "overlay.png"
        canvas = work_dir / "background.png"
        icon_source = work_dir / "icon-source.png"
        app_icon = work_dir / "icon.png"
        overlay_svg.write_text(overlay_text, encoding="utf-8")

        subprocess.run(
            command + ["-background", "none", str(overlay_svg), str(overlay_png)],
            check=True,
        )
        subprocess.run(
            command + [str(background), "-resize", f"{WIDTH}x{HEIGHT}!", str(canvas)],
            check=True,
        )
        subprocess.run(
            command
            + [
                "-background",
                "none",
                str(icon),
                "-resize",
                "256x256",
                str(icon_source),
            ],
            check=True,
        )
        subprocess.run(
            command + [str(icon_source), "-resize", "142x142", str(app_icon)],
            check=True,
        )
        subprocess.run(
            command
            + [
                str(canvas),
                str(overlay_png),
                "-composite",
                str(app_icon),
                "-geometry",
                "+76+155",
                "-composite",
                "-strip",
                str(output),
            ],
            check=True,
        )

    print(f"Rendered {args.variant}: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
