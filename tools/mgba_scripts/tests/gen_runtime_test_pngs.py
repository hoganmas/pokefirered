#!/usr/bin/env python3
"""Generate deterministic indexed PNG test sprites (64x64, 16-color)."""

from __future__ import annotations

import argparse
import os
import struct
import zlib


def _chunk(tag: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + tag
        + payload
        + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    )


def _make_indexed_png(path: str, invert: bool) -> None:
    width = 64
    height = 64

    # 16-color palette (48 bytes): black + some vivid colors.
    palette = bytes(
        [
            0x00,
            0x00,
            0x00,
            0xFF,
            0x00,
            0x00,
            0x00,
            0xFF,
            0x00,
            0x00,
            0x00,
            0xFF,
            0xFF,
            0xFF,
            0x00,
            0xFF,
            0x00,
            0xFF,
            0x00,
            0xFF,
            0xFF,
            0xFF,
            0x80,
            0x00,
            0x80,
            0xFF,
            0x00,
            0x80,
            0x00,
            0xFF,
            0x40,
            0x40,
            0x40,
            0x80,
            0x80,
            0x80,
            0xC0,
            0xC0,
            0xC0,
            0xFF,
            0x80,
            0x40,
            0x40,
            0xFF,
            0x80,
            0x80,
            0x40,
            0xFF,
        ]
    )

    rows = bytearray()
    for y in range(height):
        rows.append(0)  # filter type 0
        for x in range(0, width, 2):
            left = ((x // 4) + (y // 4)) % 16
            right = (((x + 2) // 4) + (y // 4)) % 16
            if invert:
                left = 15 - left
                right = 15 - right
            rows.append((left << 4) | right)

    ihdr = struct.pack(">IIBBBBB", width, height, 4, 3, 0, 0, 0)  # indexed, 4bpp
    idat = zlib.compress(bytes(rows), level=9)

    data = bytearray()
    data.extend(b"\x89PNG\r\n\x1a\n")
    data.extend(_chunk(b"IHDR", ihdr))
    data.extend(_chunk(b"PLTE", palette))
    data.extend(_chunk(b"IDAT", idat))
    data.extend(_chunk(b"IEND", b""))

    with open(path, "wb") as f:
        f.write(data)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    _make_indexed_png(os.path.join(args.outdir, "front.png"), invert=False)
    _make_indexed_png(os.path.join(args.outdir, "back.png"), invert=True)


if __name__ == "__main__":
    main()
