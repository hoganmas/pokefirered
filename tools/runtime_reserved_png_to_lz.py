#!/usr/bin/env python3
"""Convert front/back Pokémon PNGs into LZ77 assets matching FireRed's mon pic tables.

Used by mGBA Lua (tools/mgba_scripts/reserved_species_mailbox.lua) for runtime gfx swaps.
Writes into --workdir:
  front.4bpp.lz, back.4bpp.lz, normal.gbapal.lz, shiny.gbapal.lz (shiny == normal), manifest.txt

manifest.txt format (ASCII, KEY=VALUE per line):
  FRONT_UNCOMP=<decimal>
  BACK_UNCOMP=<decimal>
  FRONT_LZ=<decimal>
  BACK_LZ=<decimal>
  PAL_LZ=<decimal>
  SHINY_LZ=<decimal>
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys


def run_cmd(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def lz_uncompressed_size(path: str) -> int:
    with open(path, "rb") as f:
        hdr = f.read(4)
    if len(hdr) < 4 or hdr[0] != 0x10:
        raise ValueError(f"{path}: expected LZ77 header 0x10")
    return hdr[1] | (hdr[2] << 8) | (hdr[3] << 16)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--front", required=True, help="Front sprite PNG path")
    ap.add_argument("--back", required=True, help="Back sprite PNG path")
    ap.add_argument("--workdir", required=True, help="Output directory (must exist or will be created)")
    args = ap.parse_args()

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    gfx = os.path.join(repo_root, "tools", "gbagfx", "gbagfx")
    if not os.path.isfile(gfx):
        print(f"missing gbagfx: {gfx}", file=sys.stderr)
        sys.exit(1)

    work = os.path.abspath(args.workdir)
    os.makedirs(work, exist_ok=True)

    front_png = os.path.join(work, "front.png")
    back_png = os.path.join(work, "back.png")
    shutil.copyfile(os.path.abspath(args.front), front_png)
    shutil.copyfile(os.path.abspath(args.back), back_png)

    front_4bpp = os.path.join(work, "front.4bpp")
    back_4bpp = os.path.join(work, "back.4bpp")
    front_lz = os.path.join(work, "front.4bpp.lz")
    back_lz = os.path.join(work, "back.4bpp.lz")
    normal_gbapal = os.path.join(work, "normal.gbapal")
    normal_lz = os.path.join(work, "normal.gbapal.lz")
    shiny_lz = os.path.join(work, "shiny.gbapal.lz")

    run_cmd([gfx, front_png, front_4bpp, "-num_tiles", "64"])
    run_cmd([gfx, front_4bpp, front_lz])
    run_cmd([gfx, back_png, back_4bpp, "-num_tiles", "64"])
    run_cmd([gfx, back_4bpp, back_lz])
    run_cmd([gfx, front_png, normal_gbapal])
    run_cmd([gfx, normal_gbapal, normal_lz])
    shutil.copyfile(normal_lz, shiny_lz)

    fu = lz_uncompressed_size(front_lz)
    bu = lz_uncompressed_size(back_lz)
    fl = os.path.getsize(front_lz)
    bl = os.path.getsize(back_lz)
    pl = os.path.getsize(normal_lz)
    sl = os.path.getsize(shiny_lz)

    manifest = os.path.join(work, "manifest.txt")
    with open(manifest, "w", encoding="ascii") as f:
        f.write(f"FRONT_UNCOMP={fu}\n")
        f.write(f"BACK_UNCOMP={bu}\n")
        f.write(f"FRONT_LZ={fl}\n")
        f.write(f"BACK_LZ={bl}\n")
        f.write(f"PAL_LZ={pl}\n")
        f.write(f"SHINY_LZ={sl}\n")


if __name__ == "__main__":
    main()
