#!/usr/bin/env python3
"""Generates the 9-slice frame texture of the "GIDEON" card style, deterministically.

WHY A GENERATED FILE: the intermission cards of a style are only DATA
(Core/Layout.BUTTON_STYLES); the GIDEON style needs a FRAME texture the client
can slice in 9 pieces (SetBackdrop's `edgeFile`), and that texture has to exist
as a real addon asset. This tool writes it from pure arithmetic - no Pillow, no
source image, no hand-made binary - so the file can be REGENERATED at any time
and byte-compared:

    python3 tools/make_gideon_frame.py            # writes Texture/gideon-frame.tga
    python3 tools/make_gideon_frame.py --check    # writes nothing, verifies the file

FORMAT: 32-bit UNCOMPRESSED TGA (image type 2), 8 bits per channel + 8 bits of
alpha, exactly like the raid lead's screenshots converted by
tools/make_textures.py. The size is a POWER OF TWO (64x64) even though the client
accepts others (the delivered orb screenshots are 256x241 and display fine): a
power of two is the safe choice for a texture that is stretched edge by edge.

CONTENT: WHITE pixels whose ALPHA carries the shape, so the colour comes from the
game (SetBackdropBorderColor): a 2 px border, a soft inner halo (the "glow" of
the GIDEON visual) fading out, and a slightly heavier corner stud. A transparent
centre: the picture of the card is drawn inside the padding, never under the
border.

The header is checked before the file is accepted, and the declared size lives in
Core/Textures.lua (Textures.GIDEON_FRAME_SIZE): tests/spec/texture_spec.lua reads
the real header of this file and fails if the two ever disagree.
"""

from __future__ import annotations

import argparse
import os
import sys

SIZE = 64  # power of two: 4 corners of 16 px + stretched edges
BORDER_PX = 2  # fully opaque ring (the gold border at rest)
HALO_START = 3  # first pixel of the inner halo
HALO_END = 9  # last pixel of the inner halo (alpha reaches 0)
HALO_ALPHA = 0.45  # alpha of the first halo pixel
CORNER_STUD = 4  # size, in px, of the heavier corner block
CORNER_ALPHA = 1.0

TGA_HEADER_SIZE = 18
TGA_NO_COLOR_MAP = 0
TGA_TYPE_UNCOMPRESSED_TRUE_COLOR = 2
TGA_BITS_32 = 32
TGA_DESCRIPTOR_ALPHA_BITS = 8  # 8 alpha bits, origin bottom-left
FILE_NAME = "gideon-frame.tga"


def distance_to_edge(x: int, y: int, size: int) -> int:
    """Distance, in pixels, from (x, y) to the closest edge of a size x size box."""
    return min(x, y, size - 1 - x, size - 1 - y)


def alpha_at(x: int, y: int, size: int) -> int:
    """The alpha (0..255) of one pixel: border, halo, corner stud, or nothing."""
    d = distance_to_edge(x, y, size)
    # Corner studs: a small heavier block in each corner (the "filigree" of the
    # GIDEON visual, and it survives the 9-slice because it sits inside the
    # 16 px corner region).
    if (x < CORNER_STUD or x >= size - CORNER_STUD) and (y < CORNER_STUD or y >= size - CORNER_STUD):
        if d < CORNER_STUD:
            return int(round(CORNER_ALPHA * 255))
    if d < BORDER_PX:
        return 255
    if d == BORDER_PX:
        return 230
    if HALO_START <= d <= HALO_END:
        span = HALO_END - HALO_START + 1
        weight = (HALO_END - d + 1) / span
        return int(round(HALO_ALPHA * weight * 255))
    return 0


def pixels(size: int) -> bytes:
    """The BGRA rows of the image, BOTTOM-UP (the TGA default origin)."""
    out = bytearray()
    for row in range(size - 1, -1, -1):  # bottom-up
        for column in range(size):
            a = alpha_at(column, row, size)
            # WHITE, whatever the alpha: the colour is applied by the game.
            out += bytes((255, 255, 255, a))  # B, G, R, A
    return bytes(out)


def tga_bytes(size: int) -> bytes:
    header = bytearray(TGA_HEADER_SIZE)
    header[2] = TGA_TYPE_UNCOMPRESSED_TRUE_COLOR
    header[12] = size & 0xFF
    header[13] = (size >> 8) & 0xFF
    header[14] = size & 0xFF
    header[15] = (size >> 8) & 0xFF
    header[16] = TGA_BITS_32
    header[17] = TGA_DESCRIPTOR_ALPHA_BITS
    return bytes(header) + pixels(size)


def check_header(path: str) -> tuple[int, int, int, int]:
    """Reads the TGA header back: (type, width, height, bits per pixel)."""
    with open(path, "rb") as handle:
        header = handle.read(TGA_HEADER_SIZE)
    if len(header) < TGA_HEADER_SIZE:
        raise IOError(f"{path}: too short for a TGA header")
    image_type = header[2]
    width = header[12] | (header[13] << 8)
    height = header[14] | (header[15] << 8)
    bits = header[16]
    return image_type, width, height, bits


def main(argv: list[str]) -> int:
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out-dir", default=os.path.join(repo, "Texture"), help="output folder (default: Texture/)")
    parser.add_argument("--check", action="store_true", help="write nothing, only verify the file on disk")
    args = parser.parse_args(argv[1:])

    target = os.path.join(args.out_dir, FILE_NAME)
    expected = tga_bytes(SIZE)

    if args.check:
        if not os.path.isfile(target):
            print(f"MISSING {target}")
            return 1
        with open(target, "rb") as handle:
            current = handle.read()
        if current != expected:
            print(f"DIFFERENT {target} ({len(current)} bytes on disk, {len(expected)} expected)")
            return 1
        print(f"OK {target} ({len(expected)} bytes, identical to the generated content)")
        return 0

    os.makedirs(args.out_dir, exist_ok=True)
    with open(target, "wb") as handle:
        handle.write(expected)

    image_type, width, height, bits = check_header(target)
    print(f"OK {target} = {width}x{height}, {bits} bits, type {image_type}, {len(expected)} bytes")
    print(f"  power of two : {width == height and (width & (width - 1)) == 0}")
    print("  report in Core/Textures.lua :")
    print(f'    Textures.GIDEON_FRAME_SIZE = {{ {width}, {height} }}')
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
