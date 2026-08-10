#!/usr/bin/env python3
"""Copy the image-bundled GSAP runtime into a mounted video project."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


SOURCE = Path("/opt/skills-video-engine/vendor/gsap.min.js")
PROJECT_ROOT = Path("/project")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Copy the bundled GSAP runtime into /project."
    )
    parser.add_argument(
        "destination",
        nargs="?",
        default="video/assets/gsap.min.js",
        help="Destination path beneath /project.",
    )
    args = parser.parse_args()

    requested = Path(args.destination)
    destination = (
        requested.resolve()
        if requested.is_absolute()
        else (Path.cwd() / requested).resolve()
    )
    project_root = PROJECT_ROOT.resolve()
    if destination != project_root and project_root not in destination.parents:
        parser.error("destination must remain beneath /project")
    if not SOURCE.is_file():
        raise SystemExit(f"bundled GSAP runtime is missing: {SOURCE}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SOURCE, destination)
    print(f"Copied GSAP runtime to {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
