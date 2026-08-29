#!/usr/bin/env python3
"""Create a same-canvas overlay and difference image for UI calibration."""

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageEnhance


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path)
    parser.add_argument("simulator", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    reference = Image.open(args.reference).convert("RGB")
    simulator = Image.open(args.simulator).convert("RGB")
    if simulator.size != reference.size:
        simulator = simulator.resize(reference.size, Image.Resampling.LANCZOS)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.blend(reference, simulator, 0.5).save(args.output)
    difference = ImageChops.difference(reference, simulator)
    diff_path = args.output.with_name(f"{args.output.stem}-diff{args.output.suffix}")
    ImageEnhance.Contrast(difference).enhance(3.0).save(diff_path)
    print(f"overlay: {args.output} ({reference.width}x{reference.height})")
    print(f"diff: {diff_path}")


if __name__ == "__main__":
    main()
