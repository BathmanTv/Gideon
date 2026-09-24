#!/usr/bin/env python3
"""Converts the raid lead's orb screenshots into the textures of the addon.

WHY THIS TOOL EXISTS
  The retail client does NOT accept a PNG for an addon texture: the three
  composition buttons of the intermission panel display TGA files. The raid lead
  delivers SCREENSHOTS (RGBA PNG, transparent background); this tool turns them
  into the exact files the client can load, so the conversion is reproducible and
  reviewable instead of being a one-off manual export.

WHAT IT PRODUCES
  Texture/<state>.tga for the three canonical states (3V1R / 2V2R / 1V3R):
    - 32 bits, UNCOMPRESSED true-color TGA (image type 2, 32 bpp, alpha kept);
    - fitted into a 256x256 box WITH the aspect ratio preserved (the longest
      side is exactly 256 px, the other one follows the source ratio);
    - transparent background preserved, and the color of the transparent pixels
      is BLEEDED from the nearest opaque pixel (otherwise the in-game bilinear
      filtering would blend the orbs with transparent BLACK and draw a dark
      fringe around every orb);
    - resized in PREMULTIPLIED alpha (the weight of a pixel is its alpha), which
      is the only way a resize cannot pull the transparent background into the
      orbs.

  The sizes it prints are the ones to keep in `Core/Textures.lua`
  (`Textures.SIZES_BY_STATE`): the pure module cannot read a file, so the
  dimensions are DATA there, and tests/spec/texture_spec.lua asserts that the
  data matches the real header of the TGA on disk.

USAGE
  python3 tools/make_textures.py --source-dir /root/.hermes/images
  python3 tools/make_textures.py --source-dir DIR --out-dir Texture --box 256

  Nothing else in the repository has to change: the file names are the CONTRACT
  with Core/Textures.lua (same names, same folder).
"""

from __future__ import annotations

import argparse
import os
import sys

from PIL import Image

# Source -> canonical state. The mapping is the CONFIRMED one (the raid lead's
# screenshots): 3 green + 1 red = CHASER, 2 green + 2 red = MIDDLE/BOSS,
# 1 green + 3 red = ANCHOR/PING. A wrongly swapped pair would send players to
# their death, so the mapping lives in ONE table and is reviewed by eye.
SOURCES = (
    ("3V1R", "upload_20260924_222400_1.png"),  # 3 green + 1 red
    ("2V2R", "upload_20260924_222400_2.png"),  # 2 green + 2 red
    ("1V3R", "upload_20260924_222401_3.png"),  # 1 green + 3 red
)

# Fitted box, in pixels: Core/Textures.lua declares the same value.
BOX = 256

# How many dilation passes spread the opaque color under the transparent
# background. 6 px is far more than the ~2 px the filtering of a 256 px texture
# ever reaches, and it costs nothing.
BLEED_PASSES = 6

TGA_IMAGE_TYPE_UNCOMPRESSED_TRUE_COLOR = 2
TGA_BITS_PER_PIXEL_RGBA = 32
# Attributes (bits 0-3) = 8 bits of alpha. Pillow writes 0 in that field; the
# TGA specification asks for the real depth, and a strict loader reads it.
TGA_DESCRIPTOR_ALPHA_BITS = 0x08


def fit_box(width: int, height: int, box: int) -> tuple[int, int]:
    """Source size -> size fitted in a `box` x `box` square, ratio preserved."""
    if width <= 0 or height <= 0:
        raise ValueError(f"taille source invalide: {width}x{height}")
    scale = box / max(width, height)
    fitted_w = max(1, int(round(width * scale)))
    fitted_h = max(1, int(round(height * scale)))
    if fitted_w > box:
        fitted_w = box
    if fitted_h > box:
        fitted_h = box
    return fitted_w, fitted_h


def bleed_alpha(image: Image.Image, passes: int = BLEED_PASSES) -> Image.Image:
    """Gives every fully transparent pixel the color of the nearest opaque one.

    TGA stores RGBA, so a transparent pixel still carries RGB. Left at (0,0,0)
    it drags the orbs towards black as soon as the client filters the texture.
    """
    image = image.convert("RGBA")
    width, height = image.size
    pixels = list(image.getdata())
    known = [px[3] > 0 for px in pixels]
    if not any(known):
        return image
    for _ in range(passes):
        pending = []
        for y in range(height):
            row = y * width
            for x in range(width):
                index = row + x
                if known[index]:
                    continue
                total_r = total_g = total_b = count = 0
                for dy in (-1, 0, 1):
                    ny = y + dy
                    if ny < 0 or ny >= height:
                        continue
                    for dx in (-1, 0, 1):
                        nx = x + dx
                        if nx < 0 or nx >= width:
                            continue
                        neighbour = ny * width + nx
                        if not known[neighbour]:
                            continue
                        px = pixels[neighbour]
                        total_r += px[0]
                        total_g += px[1]
                        total_b += px[2]
                        count += 1
                if count:
                    pending.append((index, total_r // count, total_g // count, total_b // count))
        if not pending:
            break
        for index, red, green, blue in pending:
            pixels[index] = (red, green, blue, 0)
            known[index] = True
    out = Image.new("RGBA", (width, height))
    out.putdata(pixels)
    return out


def premultiplied_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Resize in premultiplied alpha, then unpremultiply (no dark halo)."""
    source_image = image.convert("RGBA")
    width, height = source_image.size
    source = list(source_image.getdata())
    # Premultiply.
    flat = []
    for px in source:
        alpha = px[3] / 255.0
        flat.append((int(px[0] * alpha + 0.5), int(px[1] * alpha + 0.5), int(px[2] * alpha + 0.5), px[3]))
    premul = Image.new("RGBA", (width, height))
    premul.putdata(flat)
    resized = premul.resize(size, Image.LANCZOS)
    target = list(resized.getdata())
    out = []
    for red, green, blue, alpha in target:
        if alpha == 0:
            out.append((red, green, blue, 0))
            continue
        scale = 255.0 / alpha
        out.append(
            (
                min(255, int(red * scale + 0.5)),
                min(255, int(green * scale + 0.5)),
                min(255, int(blue * scale + 0.5)),
                alpha,
            )
        )
    result = Image.new("RGBA", size)
    result.putdata(out)
    return result


def save_tga(image: Image.Image, path: str) -> None:
    image.convert("RGBA").save(path, format="TGA")
    # Pillow leaves the "attributes" field of the image descriptor at 0: declare
    # the 8 bits of alpha, as the TGA specification asks.
    with open(path, "r+b") as handle:
        handle.seek(17)
        descriptor = handle.read(1)
        if len(descriptor) != 1:
            raise IOError(f"{path}: en-tete TGA tronque")
        handle.seek(17)
        handle.write(bytes([descriptor[0] | TGA_DESCRIPTOR_ALPHA_BITS]))


def check_header(path: str) -> tuple[int, int, int, int]:
    """Reads the TGA header back: (type, width, height, bits per pixel)."""
    with open(path, "rb") as handle:
        header = handle.read(18)
    if len(header) < 18:
        raise IOError(f"{path}: fichier trop court pour un en-tete TGA")
    image_type = header[2]
    width = header[12] | (header[13] << 8)
    height = header[14] | (header[15] << 8)
    bits = header[16]
    return image_type, width, height, bits


def main(argv: list[str]) -> int:
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-dir", required=True, help="folder holding the raid lead's PNG screenshots")
    parser.add_argument("--out-dir", default=os.path.join(repo, "Texture"), help="output folder (default: Texture/)")
    parser.add_argument("--box", type=int, default=BOX, help=f"fitted box in pixels (default: {BOX})")
    args = parser.parse_args(argv)

    os.makedirs(args.out_dir, exist_ok=True)
    failed = False
    for state, name in SOURCES:
        source = os.path.join(args.source_dir, name)
        if not os.path.isfile(source):
            print(f"ECHEC: {source} introuvable", file=sys.stderr)
            failed = True
            continue
        with Image.open(source) as raw:
            image = raw.convert("RGBA")
        width, height = fit_box(*image.size, args.box)
        prepared = bleed_alpha(image)
        resized = premultiplied_resize(prepared, (width, height))
        target = os.path.join(args.out_dir, f"{state.lower()}.tga")
        save_tga(resized, target)
        image_type, header_w, header_h, bits = check_header(target)
        ok = (
            image_type == TGA_IMAGE_TYPE_UNCOMPRESSED_TRUE_COLOR
            and bits == TGA_BITS_PER_PIXEL_RGBA
            and (header_w, header_h) == (width, height)
        )
        status = "OK" if ok else "ECHEC"
        if not ok:
            failed = True
        print(f"{status} {os.path.basename(target)} <- {name} ({image.size[0]}x{image.size[1]}) = {width}x{height}, {bits} bits, type {image_type}")

    print("")
    print("A reporter dans Core/Textures.lua (Textures.SIZES_BY_STATE):")
    for state, name in SOURCES:
        target = os.path.join(args.out_dir, f"{state.lower()}.tga")
        if os.path.isfile(target):
            _, header_w, header_h, _ = check_header(target)
            print(f'    ["{state}"] = {{ {header_w}, {header_h} }},')
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
