#!/usr/bin/env python3
"""Generates the rounded-corner art used by CastQueueOverlayStyle.lua.

Checked in as a SCRIPT rather than only as its output, because the two .tga
files are the one part of this addon nobody can read. A binary blob in the repo
with no way to regenerate it is a blob that can never be adjusted - and the
corner radius is exactly the kind of thing that gets adjusted.

Two files, both 32x32, both white with the shape carried entirely in the alpha
channel so they can be tinted to any colour with SetVertexColor:

  rounded.tga          a filled rounded rectangle, used as a MASK
  rounded-outline.tga  the ring of that rectangle, used as the border

Both are nine-sliced at RADIUS, so the corners are drawn at their native size
and only the straight edges stretch. That is what keeps the radius constant on
a 700px window and on a 16px button, which a plain stretched texture cannot do.

  python dev/make_art.py
"""

import math
import os
import struct

SIZE = 32
RADIUS = 8          # must match RADIUS in CastQueueOverlayStyle.lua
THICKNESS = 1.0     # outline, in texels
SUPERSAMPLE = 4     # per axis, so 16 samples per pixel

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "art")


def inside_rounded_rect(x, y, size, radius):
    """True when (x, y) falls inside a rounded rect of `size` with `radius`.

    The bounds test comes FIRST and is not optional. Without it the corner test
    below reads "outside on x but inside on y" as inside, because it only asks
    whether either axis has cleared the corner square - which is correct only
    for a point already known to be within the rectangle. The outline is built
    by sampling this at NEGATIVE coordinates, so it hit that case immediately:
    the ring came out as four corner arcs with no straight edges joining them.
    """
    if x < 0 or y < 0 or x > size or y > size:
        return False

    # Fold into the top-left quadrant; the shape is symmetric on both axes.
    cx = min(x, size - x)
    cy = min(y, size - y)
    if cx >= radius or cy >= radius:
        return True
    dx = radius - cx
    dy = radius - cy
    return dx * dx + dy * dy <= radius * radius


def coverage(px, py, size, radius):
    """Antialiased coverage of one pixel, by supersampling.

    A hard in/out test gives stair-stepped corners that look like a rendering
    fault rather than a design choice, and no amount of pixel snapping fixes it
    because the jaggedness is baked into the texture.
    """
    hits = 0
    step = 1.0 / SUPERSAMPLE
    for sy in range(SUPERSAMPLE):
        for sx in range(SUPERSAMPLE):
            x = px + (sx + 0.5) * step
            y = py + (sy + 0.5) * step
            if inside_rounded_rect(x, y, size, radius):
                hits += 1
    return hits / float(SUPERSAMPLE * SUPERSAMPLE)


def write_tga(path, alpha_rows):
    """Uncompressed 32-bit BGRA TGA, top-left origin.

    Orientation is not a risk here even if a reader disagrees about it: both
    shapes are symmetric on both axes, so a flip is invisible.
    """
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,          # id length
        0,          # no colour map
        2,          # uncompressed true-colour
        0, 0, 0,    # colour map spec
        0, 0,       # x, y origin
        SIZE, SIZE,
        32,         # bits per pixel
        0x28,       # 8 alpha bits, top-left origin
    )

    body = bytearray()
    for row in alpha_rows:
        for a in row:
            value = int(round(a * 255))
            # BGRA. White throughout, so the shape lives only in alpha and the
            # texture can be tinted to anything.
            body += bytes((255, 255, 255, value))

    with open(path, "wb") as handle:
        handle.write(header)
        handle.write(bytes(body))
    print("wrote %s (%d bytes)" % (path, 18 + len(body)))


def main():
    os.makedirs(OUT, exist_ok=True)

    filled = [[coverage(x, y, SIZE, RADIUS) for x in range(SIZE)]
              for y in range(SIZE)]

    # The ring is the filled shape minus the same shape inset by THICKNESS.
    # Deriving it rather than drawing it separately is what guarantees the two
    # curves are concentric - an outline drawn independently drifts from the
    # mask it is supposed to sit on, and the gap shows at the corners.
    inner_size = SIZE - THICKNESS * 2
    inner_radius = max(0.0, RADIUS - THICKNESS)
    outline = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            inner = coverage(x - THICKNESS, y - THICKNESS,
                             inner_size, inner_radius)
            row.append(max(0.0, filled[y][x] - inner))
        outline.append(row)

    write_tga(os.path.join(OUT, "rounded.tga"), filled)
    write_tga(os.path.join(OUT, "rounded-outline.tga"), outline)


if __name__ == "__main__":
    main()
