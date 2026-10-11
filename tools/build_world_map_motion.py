"""Encode the GPU suite's review frames as a lossless animated WebP.

Run after tools/run_tests.ps1 -WorldMap. Requires Pillow.
"""
from pathlib import Path

from PIL import Image


def main() -> None:
    project = Path(__file__).resolve().parent.parent
    paths = sorted((project / "artifacts/world-map-motion").glob("frame-*.png"))
    if len(paths) != 32:
        raise SystemExit("Expected 32 review frames; run the WorldMap suite first.")
    frames = [Image.open(path).convert("RGB") for path in paths]
    output = project / "docs/world-map-art-motion.webp"
    frames[0].save(
        output,
        save_all=True,
        append_images=frames[1:],
        duration=250,
        loop=0,
        lossless=True,
        method=4,
    )
    with Image.open(output) as animation:
        assert animation.n_frames == 32
        assert animation.size == (960, 540)
    print(f"Wrote {output.name}: 32 frames, 8 seconds, 960 x 540")


if __name__ == "__main__":
    main()
